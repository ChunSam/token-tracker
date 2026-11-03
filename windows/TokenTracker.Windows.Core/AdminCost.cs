using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

// Stage 2 of docs/cost-display-design.md: what an organization's Admin API key
// says it has spent this month. Collection only — nothing here reaches the
// screen yet. Mirrors Sources/TokenTrackerCore/AdminCost.swift.

/// This month's spend for one provider, as its Admin API last reported it.
/// <param name="MonthToDate">From local midnight on the 1st. Null while nothing is tallied.</param>
/// <param name="Today">From local midnight today. Null while today is not tallied
/// yet, or when the provider's days do not start at local midnight.</param>
/// <param name="TopItems">The month's largest models (Anthropic) or line items (OpenAI), at most three.</param>
/// <param name="DataRefreshedAt">Complete up to here: Anthropic's <c>data_refreshed_at</c>.
/// Null for OpenAI, whose cost shows up within minutes, and while nothing is tallied.</param>
public sealed record ProviderCost(
    Provider Provider,
    CostAmount? MonthToDate,
    CostAmount? Today,
    IReadOnlyList<CostLineItem> TopItems,
    DateTimeOffset? DataRefreshedAt,
    DateTimeOffset MeasuredAt);

public enum CostFetchFailureKind
{
    /// 401 or 403: a wrong, revoked or non-admin key. Fixed only by a new key.
    KeyRejected,
    RateLimited,
    Failed
}

/// <param name="Message">In English, for diagnostics.</param>
public sealed record CostFetchFailure(CostFetchFailureKind Kind, string Message);

/// Either a reading or why there is none.
public sealed record CostFetchResult(ProviderCost? Cost, CostFetchFailure? Failure)
{
    public static CostFetchResult Of(ProviderCost cost) => new(cost, null);

    public static CostFetchResult Failed(CostFetchFailureKind kind, string message) =>
        new(null, new CostFetchFailure(kind, message));
}

/// What each Admin API is asked. Brackets in parameter names go percent-encoded,
/// as the providers' own SDKs send them.
public static class AdminCostRequest
{
    private const string AnthropicEndpoint = "https://api.anthropic.com/v1/organizations/analytics/cost";
    private const string OpenAIEndpoint = "https://api.openai.com/v1/organization/costs";

    /// Hourly buckets, for this month's and today's totals. Null while the range is
    /// under an hour once both ends are rounded down to the hour, as the API rounds
    /// them: the first hour of a month has nothing to ask for yet.
    public static Uri? AnthropicHourly(DateTimeOffset start, DateTimeOffset end, string? page) =>
        CoversAnHour(start, end)
            ? Build(AnthropicEndpoint, page,
                ("starting_at", IsoString(start)),
                ("ending_at", IsoString(end)),
                ("time_bucket_width", "1h"),
                ("limit", "1000"))
            : null;

    /// One row per model across the whole range, for the split.
    public static Uri? AnthropicByModel(DateTimeOffset start, DateTimeOffset end, string? page) =>
        CoversAnHour(start, end)
            ? Build(AnthropicEndpoint, page,
                ("starting_at", IsoString(start)),
                ("ending_at", IsoString(end)),
                ("group_by%5B%5D", "model"),
                ("limit", "100"))
            : null;

    /// Day buckets, split by line item. <c>limit</c> counts days, so a month fits in
    /// one page unless the days are cut at UTC midnight and the 1st spills into a 32nd.
    public static Uri? OpenAI(DateTimeOffset start, DateTimeOffset end, string? page)
    {
        var startSeconds = start.ToUnixTimeSeconds();
        var endSeconds = end.ToUnixTimeSeconds();
        if (endSeconds <= startSeconds)
        {
            return null;
        }

        return Build(OpenAIEndpoint, page,
            ("start_time", startSeconds.ToString(CultureInfo.InvariantCulture)),
            ("end_time", endSeconds.ToString(CultureInfo.InvariantCulture)),
            ("bucket_width", "1d"),
            ("group_by%5B%5D", "line_item"),
            ("limit", "31"));
    }

    public static IReadOnlyList<(string Name, string Value)> Headers(Provider provider, string key) =>
        provider == Provider.Claude
            ? new[]
            {
                ("x-api-key", key),
                ("anthropic-version", "2023-06-01"),
                ("anthropic-beta", "analytics-usage-cost-2026-08-24"),
                ("Accept", "application/json")
            }
            : new[]
            {
                ("Authorization", "Bearer " + key),
                ("Accept", "application/json")
            };

    private static bool CoversAnHour(DateTimeOffset start, DateTimeOffset end) =>
        end.ToUnixTimeSeconds() / 3600 > start.ToUnixTimeSeconds() / 3600;

    private static Uri Build(string endpoint, string? page, params (string Name, string Value)[] query)
    {
        var pairs = query.Select(pair => pair.Name + "=" + pair.Value).ToList();
        if (page is not null)
        {
            pairs.Add("page=" + Uri.EscapeDataString(page));
        }

        return new Uri(endpoint + "?" + string.Join("&", pairs));
    }

    internal static string IsoString(DateTimeOffset date) =>
        date.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
}

/// Asks one provider's Admin API for this month's cost, every page of it.
public sealed class AdminCostClient
{
    /// More pages than a month can fill: the cursor is going round in circles.
    private const int MaxPages = 10;
    private static readonly TimeSpan DefaultRateLimitCooldown = TimeSpan.FromMinutes(5);

    private readonly HttpClient http;
    private readonly ProviderRateLimitState rateLimitState;

    public AdminCostClient(Provider provider, HttpClient? http = null, string? rateLimitStatePath = null)
    {
        Provider = provider;
        this.http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        rateLimitState = new ProviderRateLimitState(
            new ProviderRateLimitStore(rateLimitStatePath ?? AppPaths.AdminCostRateLimitStatePath(provider)));
    }

    public Provider Provider { get; }

    private string ServiceName => Provider == Provider.Claude ? "Anthropic Admin API" : "OpenAI Admin API";

    public async Task<CostFetchResult> FetchAsync(
        string key,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        var fingerprint = TokenFingerprint.Of(key);
        if (rateLimitState.CurrentError(ServiceName, fingerprint) is { } limited)
        {
            return CostFetchResult.Failed(CostFetchFailureKind.RateLimited, limited.Message);
        }

        try
        {
            var cost = await FetchCostAsync(key, now, timeZone, cancellationToken);
            rateLimitState.Clear();
            return CostFetchResult.Of(cost);
        }
        catch (UsageHttpException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
        {
            rateLimitState.BackOff(ex.RetryAfter ?? DefaultRateLimitCooldown, fingerprint);
            return CostFetchResult.Failed(
                CostFetchFailureKind.RateLimited,
                rateLimitState.CurrentError(ServiceName, fingerprint)?.Message ?? ex.Message);
        }
        catch (UsageHttpException ex) when (ex.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            return CostFetchResult.Failed(CostFetchFailureKind.KeyRejected, ex.Message);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return CostFetchResult.Failed(CostFetchFailureKind.Failed, "Timed out contacting " + ServiceName);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return CostFetchResult.Failed(CostFetchFailureKind.Failed, ex.Message);
        }
    }

    private async Task<ProviderCost> FetchCostAsync(
        string key,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken)
    {
        var (start, end) = CostPeriod.RequestRange(now, timeZone);
        var totals = Provider == Provider.Claude
            ? await AllPagesAsync(key, AnthropicCostParser.Page, page => AdminCostRequest.AnthropicHourly(start, end, page), cancellationToken)
            : await AllPagesAsync(key, OpenAICostParser.Page, page => AdminCostRequest.OpenAI(start, end, page), cancellationToken);
        var report = CostAggregator.Report(totals.Buckets, totals.Freshness, now, timeZone);

        // Anthropic splits by model in a query of its own, worth asking only once
        // the month has something in it.
        var items = totals.Items;
        if (Provider == Provider.Claude)
        {
            items = Array.Empty<CostLineItem>();
            if (report.MonthToDate is not null)
            {
                var models = await AllPagesAsync(
                    key,
                    AnthropicCostParser.Page,
                    page => AdminCostRequest.AnthropicByModel(start, end, page),
                    cancellationToken);
                items = models.Items;
            }
        }

        var refreshedAt = report.Freshness.Kind == CostFreshnessKind.RefreshedAt ? report.Freshness.RefreshedAt : null;
        return new ProviderCost(Provider, report.MonthToDate, report.Today, CostLineItem.Top(items), refreshedAt, now);
    }

    /// Every page of one query, joined. The pages share one snapshot of the data, so
    /// the first page's freshness speaks for all of them. No first URL means there
    /// is nothing to ask for yet.
    private async Task<CostPage> AllPagesAsync(
        string key,
        Func<string, CostPage?> parse,
        Func<string?, Uri?> url,
        CancellationToken cancellationToken)
    {
        if (url(null) is not { } next)
        {
            return new CostPage(Array.Empty<CostBucket>(), Array.Empty<CostLineItem>(), null, CostFreshness.NotTallied);
        }

        var buckets = new List<CostBucket>();
        var items = new List<CostLineItem>();
        CostFreshness? freshness = null;
        for (var index = 0; index < MaxPages; index++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, next);
            foreach (var (name, value) in AdminCostRequest.Headers(Provider, key))
            {
                request.Headers.TryAddWithoutValidation(name, value);
            }

            using var response = await http.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                throw new UsageHttpException(response.StatusCode, ServiceName, UsageClient.RetryAfter(response));
            }

            var page = parse(await response.Content.ReadAsStringAsync(cancellationToken))
                ?? throw new InvalidDataException("Invalid response");
            buckets.AddRange(page.Buckets);
            items.AddRange(page.Items);
            freshness ??= page.Freshness;
            if (page.NextPage is not { } cursor)
            {
                return new CostPage(buckets, items, null, freshness);
            }

            next = url(cursor) ?? throw new InvalidDataException("Invalid response");
        }

        // A partial month would read as a smaller bill, so it is no reading at all.
        throw new InvalidDataException("Invalid response");
    }
}

public static class CostCachePolicy
{
    /// What still holds of an earlier reading. Money spent stays spent, so the month
    /// stands until the local month turns; today stands until the local date does.
    public static ProviderCost? Usable(ProviderCost cost, DateTimeOffset now, TimeZoneInfo timeZone)
    {
        if (CostPeriod.MonthStart(cost.MeasuredAt, timeZone) != CostPeriod.MonthStart(now, timeZone))
        {
            return null;
        }

        return CostPeriod.DayStart(cost.MeasuredAt, timeZone) == CostPeriod.DayStart(now, timeZone)
            ? cost
            : cost with { Today = null };
    }
}

/// The last good reading per provider, so a relaunch or a failed fetch still has
/// one. Each is tied to the key that fetched it, by fingerprint, never the key.
public sealed class CostCacheStore
{
    public sealed record Entry(string KeyFingerprint, ProviderCost Cost);

    private sealed record Record(int Version, IReadOnlyList<Entry> Entries);

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string Path { get; }

    public CostCacheStore(string? path = null)
    {
        Path = path ?? AppPaths.CostCachePath;
    }

    public IReadOnlyList<Entry> Load()
    {
        try
        {
            if (!File.Exists(Path))
            {
                return Array.Empty<Entry>();
            }

            var record = JsonSerializer.Deserialize<Record>(File.ReadAllText(Path), Options);
            return record is { Version: 1, Entries: not null } ? record.Entries : Array.Empty<Entry>();
        }
        catch
        {
            return Array.Empty<Entry>();
        }
    }

    public void Save(IReadOnlyList<Entry> entries)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var tempPath = Path + ".tmp";
            File.WriteAllText(tempPath, JsonSerializer.Serialize(new Record(1, entries), Options));
            File.Move(tempPath, Path, overwrite: true);
        }
        catch
        {
        }
    }
}

/// One provider's Admin API cost as the app holds it between fetches.
public sealed record CostState
{
    /// Whether the user switched API cost on for this provider.
    public bool Enabled { get; init; }

    /// <c>…ab12</c> for the stored key; null with no key.
    public string? KeySuffix { get; init; }

    /// The last good reading, carried through later failures for as long as it holds.
    public ProviderCost? Cost { get; init; }

    /// Why the last fetch failed; null after a good one.
    public CostFetchFailure? Failure { get; init; }

    public DateTimeOffset? LastAttemptAt { get; init; }

    public DateTimeOffset? NextFetchAt { get; init; }

    /// The key the reading and schedule belong to. A different key starts over.
    internal string? KeyFingerprint { get; init; }

    /// The reading is an earlier one, standing in for a fetch that failed.
    public bool IsCached => Cost is not null && Failure is not null;
}

/// Fetches each provider's month of cost on its own schedule, apart from the usage
/// poll, and keeps the last good reading through failures. One caller at a time:
/// the tray's refresh, which never overlaps itself.
public sealed class AdminCostService
{
    private static readonly Provider[] Providers = { Provider.Claude, Provider.Codex };

    private readonly Dictionary<Provider, CostState> states = new();
    private readonly IAdminKeyStore keyStore;
    private readonly IReadOnlyDictionary<Provider, AdminCostClient> clients;
    private readonly CostCacheStore cacheStore;
    private bool cacheLoaded;

    public AdminCostService(
        IAdminKeyStore? keyStore = null,
        IReadOnlyDictionary<Provider, AdminCostClient>? clients = null,
        CostCacheStore? cacheStore = null)
    {
        this.keyStore = keyStore ?? new DpapiAdminKeyStore();
        this.clients = clients ?? new Dictionary<Provider, AdminCostClient>
        {
            [Provider.Claude] = new AdminCostClient(Provider.Claude),
            [Provider.Codex] = new AdminCostClient(Provider.Codex)
        };
        this.cacheStore = cacheStore ?? new CostCacheStore();
    }

    /// Fetches each switched-on provider whose turn has come, and returns where
    /// every provider stands. A key is read only for a provider that is switched
    /// on, so a user who never turns this on never has the key file opened.
    public async Task<IReadOnlyDictionary<Provider, CostState>> RefreshIfDueAsync(
        IReadOnlyDictionary<Provider, bool> enabled,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        LoadCacheIfNeeded(now, timeZone);
        foreach (var provider in Providers)
        {
            var on = enabled.TryGetValue(provider, out var value) && value;
            await RefreshAsync(provider, on, now, timeZone, cancellationToken);
        }

        return new Dictionary<Provider, CostState>(states);
    }

    private async Task RefreshAsync(
        Provider provider,
        bool enabled,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken)
    {
        var state = states.TryGetValue(provider, out var existing) ? existing : new CostState();
        state = state with { Cost = state.Cost is { } held ? CostCachePolicy.Usable(held, now, timeZone) : null };
        if (!enabled)
        {
            // Off forgets the schedule, so switching back on fetches at once.
            states[provider] = new CostState { Cost = state.Cost, KeyFingerprint = state.KeyFingerprint };
            return;
        }

        state = state with { Enabled = true };
        if (keyStore.Key(provider) is not { } key)
        {
            states[provider] = state with { KeySuffix = null, Failure = null, NextFetchAt = null };
            return;
        }

        var fingerprint = TokenFingerprint.Of(key);
        if (state.KeyFingerprint != fingerprint)
        {
            // Another key may be another organization: its reading, failures and
            // schedule were never this key's.
            state = new CostState { Enabled = true, KeyFingerprint = fingerprint };
        }

        state = state with { KeySuffix = AdminKeyText.Suffix(key) };
        if (!CostFetchPolicy.IsDue(state.NextFetchAt, now) || !clients.TryGetValue(provider, out var client))
        {
            states[provider] = state;
            return;
        }

        var result = await client.FetchAsync(key, now, timeZone, cancellationToken);
        state = state with { LastAttemptAt = now };
        if (result.Cost is { } cost)
        {
            state = state with
            {
                Cost = cost,
                Failure = null,
                NextFetchAt = CostFetchPolicy.NextFetch(now, succeeded: true)
            };
        }
        else
        {
            state = state with
            {
                Failure = result.Failure,
                NextFetchAt = CostFetchPolicy.NextFetch(now, succeeded: false)
            };
        }

        states[provider] = state;
        SaveCache();
    }

    private void LoadCacheIfNeeded(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        if (cacheLoaded)
        {
            return;
        }

        cacheLoaded = true;
        foreach (var entry in cacheStore.Load())
        {
            if (CostCachePolicy.Usable(entry.Cost, now, timeZone) is { } cost)
            {
                states[cost.Provider] = new CostState { Cost = cost, KeyFingerprint = entry.KeyFingerprint };
            }
        }
    }

    private void SaveCache()
    {
        var entries = new List<CostCacheStore.Entry>();
        foreach (var provider in Providers)
        {
            if (states.TryGetValue(provider, out var state) &&
                state.Cost is { } cost &&
                state.KeyFingerprint is { } fingerprint)
            {
                entries.Add(new CostCacheStore.Entry(fingerprint, cost));
            }
        }

        cacheStore.Save(entries);
    }
}

public static class CostDiagnostics
{
    /// What diagnostics says about one provider's API cost. Never the key: its last
    /// four characters at most.
    public static IReadOnlyList<string> Lines(Provider provider, CostState state)
    {
        var name = (provider == Provider.Claude ? "Claude" : "Codex") + " API cost";
        if (!state.Enabled)
        {
            return new[] { name + ": off" };
        }

        if (state.KeySuffix is not { } suffix)
        {
            return new[] { name + ": on, no Admin key" };
        }

        var lines = new List<string> { name + ": on, key " + suffix };
        if (state.Cost is { } cost)
        {
            var month = cost.MonthToDate is { } monthToDate ? CostFormatter.Text(monthToDate) : "not tallied";
            var today = cost.Today is { } todays ? CostFormatter.Text(todays) : "--";
            lines.Add(name + " month: " + month);
            lines.Add(name + " today: " + today);
            if (cost.DataRefreshedAt is { } refreshed)
            {
                lines.Add(name + " complete up to: " + AdminCostRequest.IsoString(refreshed));
            }

            if (cost.TopItems.Count > 0)
            {
                lines.Add(name + " top: " + string.Join(", ", cost.TopItems.Select(item => item.Name + " " + CostFormatter.Text(item.Amount))));
            }

            lines.Add(name + " measured: " + AdminCostRequest.IsoString(cost.MeasuredAt));
        }

        var outcome = state.Failure is { } failure ? KindText(failure.Kind) + ": " + failure.Message : "ok";
        var lastFetch = state.LastAttemptAt is { } attempt ? AdminCostRequest.IsoString(attempt) + " " + outcome : "none";
        lines.Add(name + " last fetch: " + lastFetch);
        return lines;
    }

    /// The same words the macOS diagnostics use.
    private static string KindText(CostFetchFailureKind kind) => kind switch
    {
        CostFetchFailureKind.KeyRejected => "keyRejected",
        CostFetchFailureKind.RateLimited => "rateLimited",
        _ => "failed"
    };
}
