using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

public sealed class UsageClient
{
    private static readonly Uri CodexUsageUrl = new("https://chatgpt.com/backend-api/wham/usage");
    private static readonly Uri ClaudeUsageUrl = new("https://api.anthropic.com/api/oauth/usage");
    private static readonly TimeSpan DefaultClaudeRateLimitCooldown = TimeSpan.FromMinutes(5);

    private readonly HttpClient http;
    private readonly CredentialReader credentialReader;
    private readonly ClaudeRateLimitState claudeRateLimitState;
    private readonly string? homeDirectory;

    public UsageClient(
        HttpClient? http = null,
        CredentialReader? credentialReader = null,
        string? homeDirectory = null,
        string? rateLimitStatePath = null)
    {
        this.http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        this.credentialReader = credentialReader ?? new CredentialReader();
        this.homeDirectory = homeDirectory;
        this.claudeRateLimitState = new ClaudeRateLimitState(
            new ClaudeRateLimitStore(rateLimitStatePath ?? AppPaths.ClaudeRateLimitStatePath));
    }

    public async Task<UsageSnapshot> RefreshAsync(CancellationToken cancellationToken = default)
    {
        var claudeTask = FetchClaudeAsync(cancellationToken);
        var codexTask = FetchCodexAsync(cancellationToken);
        await Task.WhenAll(claudeTask, codexTask);

        return new UsageSnapshot(claudeTask.Result, codexTask.Result, DateTimeOffset.Now);
    }

    public async Task<ProviderUsage> FetchCodexAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var auth = credentialReader.ReadCodexAuth(homeDirectory);

            // `codex login` refreshes this token; Token Tracker only reads it. Once
            // it lapses the endpoint answers a bare HTTP 401, which tells the user
            // nothing about needing to sign in again — so name the cause here.
            if (CredentialExpiry.IsExpired(auth.ExpiresAt))
            {
                return ProviderUsage.Unavailable(
                    Provider.Codex,
                    ExpiredCredentialsMessage("Codex API", auth.ExpiresAt));
            }

            using var request = new HttpRequestMessage(HttpMethod.Get, CodexUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
            request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", auth.AccountId);
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, "Codex API", cancellationToken);
            return UsageParser.ParseCodexUsage(json);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ProviderUsage.Unavailable(Provider.Codex, "Timed out contacting Codex API");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Codex, ex.Message);
        }
    }

    public async Task<ProviderUsage> FetchClaudeAsync(CancellationToken cancellationToken = default)
    {
        ClaudeCredential credential;
        try
        {
            credential = credentialReader.ReadClaudeCredential(homeDirectory);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Claude, ex.Message);
        }

        // The stored token has lapsed. Spending a request on it would return an
        // opaque 401 — or a 429 that the backoff below would mistake for a quota
        // cooldown — so report the real cause and drop any cooldown a previous
        // expired-token round already recorded.
        if (CredentialExpiry.IsExpired(credential.ExpiresAt))
        {
            claudeRateLimitState.Clear();
            return ProviderUsage.Unavailable(
                Provider.Claude,
                ExpiredCredentialsMessage("Claude API", credential.ExpiresAt));
        }

        // A cooldown is only binding for the credentials that earned it; signing in
        // again has to take effect immediately rather than wait it out.
        var fingerprint = TokenFingerprint.Of(credential.AccessToken);
        if (claudeRateLimitState.CurrentError("Claude API", fingerprint) is { } rateLimitError)
        {
            return ProviderUsage.Unavailable(Provider.Claude, rateLimitError.Message);
        }

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AccessToken);
            request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, "Claude API", cancellationToken);
            var usage = UsageParser.ParseClaudeUsage(json, fallbackPlan: credential.Plan);
            claudeRateLimitState.Clear();
            return usage;
        }
        catch (UsageHttpException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
        {
            claudeRateLimitState.BackOff(ex.RetryAfter ?? DefaultClaudeRateLimitCooldown, fingerprint);
            return ProviderUsage.Unavailable(
                Provider.Claude,
                claudeRateLimitState.CurrentError("Claude API", fingerprint)?.Message ?? ex.Message);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ProviderUsage.Unavailable(Provider.Claude, "Timed out contacting Claude API");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Claude, ex.Message);
        }
    }

    private static string ExpiredCredentialsMessage(string serviceName, DateTimeOffset? expiredAt)
    {
        var prefix = $"Credentials expired for {serviceName}";
        return expiredAt is { } expiry
            ? $"{prefix} (expired {expiry.ToUniversalTime():yyyy-MM-ddTHH:mm:ssZ})"
            : prefix;
    }

    private async Task<string> SendForJsonAsync(HttpRequestMessage request, string serviceName, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new UsageHttpException(response.StatusCode, serviceName, RetryAfter(response));
        }

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private static TimeSpan? RetryAfter(HttpResponseMessage response)
    {
        var retryAfter = response.Headers.RetryAfter;
        if (retryAfter?.Delta is { } delta)
        {
            return MaxZero(delta);
        }

        if (retryAfter?.Date is { } date)
        {
            return MaxZero(date - DateTimeOffset.Now);
        }

        return null;
    }

    private static TimeSpan MaxZero(TimeSpan value) =>
        value < TimeSpan.Zero ? TimeSpan.Zero : value;
}

public sealed class UsageHttpException : Exception
{
    public HttpStatusCode StatusCode { get; }
    public string ServiceName { get; }
    public TimeSpan? RetryAfter { get; }

    public UsageHttpException(HttpStatusCode statusCode, string serviceName, TimeSpan? retryAfter = null)
        : base(FormatMessage(statusCode, serviceName, retryAfter))
    {
        StatusCode = statusCode;
        ServiceName = serviceName;
        RetryAfter = retryAfter;
    }

    private static string FormatMessage(HttpStatusCode statusCode, string serviceName, TimeSpan? retryAfter)
    {
        var prefix = $"HTTP {(int)statusCode} from {serviceName}";
        return statusCode == HttpStatusCode.TooManyRequests && retryAfter is not null
            ? $"{prefix}; retrying after {FormatRetryAfter(retryAfter.Value)}"
            : prefix;
    }

    private static string FormatRetryAfter(TimeSpan retryAfter)
    {
        var seconds = Math.Max(0, (int)Math.Ceiling(retryAfter.TotalSeconds));
        if (seconds < 60)
        {
            return $"{seconds}s";
        }

        var minutes = (int)Math.Ceiling(seconds / 60.0);
        if (minutes < 60)
        {
            return $"{minutes}m";
        }

        var hours = minutes / 60;
        var remainingMinutes = minutes % 60;
        return remainingMinutes == 0 ? $"{hours}h" : $"{hours}h {remainingMinutes}m";
    }
}

internal sealed class ClaudeRateLimitState
{
    private readonly object gate = new();
    private readonly ClaudeRateLimitStore store;
    private DateTimeOffset? retryAllowedAt;
    private int failureCount;
    private string? fingerprint;
    private bool loaded;

    public ClaudeRateLimitState(ClaudeRateLimitStore store)
    {
        this.store = store;
    }

    // Seed the in-memory cooldown from disk on first use so a relaunch during a
    // cooldown does not immediately re-fire a still-rate-limited request.
    private void EnsureLoaded()
    {
        if (loaded)
        {
            return;
        }

        loaded = true;
        if (store.Load() is { } snapshot)
        {
            retryAllowedAt = snapshot.RetryAllowedAt;
            failureCount = snapshot.FailureCount;
            fingerprint = snapshot.Fingerprint;
        }
    }

    public UsageHttpException? CurrentError(string serviceName, string credentialFingerprint)
    {
        lock (gate)
        {
            EnsureLoaded();
            if (retryAllowedAt is null)
            {
                return null;
            }

            // A cooldown only binds the credentials it was recorded against. A
            // record that names different credentials — or, from a build before
            // fingerprints were stored, names none at all — cannot be shown to
            // apply to the token in hand, so the token gets a fresh attempt.
            // Dropping one costs a single request that re-establishes the cooldown
            // if the limit is real; honoring one wrongly blocks refreshes for up to
            // the full escalated cooldown.
            if (fingerprint != credentialFingerprint)
            {
                Reset();
                return null;
            }

            var remaining = retryAllowedAt.Value - DateTimeOffset.Now;
            if (remaining <= TimeSpan.Zero)
            {
                retryAllowedAt = null;
                store.Clear();
                return null;
            }

            return new UsageHttpException(HttpStatusCode.TooManyRequests, serviceName, remaining);
        }
    }

    public void BackOff(TimeSpan retryAfter, string credentialFingerprint)
    {
        lock (gate)
        {
            EnsureLoaded();
            if (fingerprint != credentialFingerprint)
            {
                // New credentials start their own backoff ladder rather than
                // inheriting escalation earned by a token no longer in use.
                failureCount = 0;
                fingerprint = credentialFingerprint;
            }

            // Escalate the cooldown per consecutive 429 and add jitter so repeated
            // rate limiting backs off further instead of retrying at a fixed cadence.
            var cooldown = RateLimitBackoff.Cooldown(
                retryAfter,
                failureCount,
                Random.Shared.NextDouble() * RateLimitBackoff.JitterFraction);
            failureCount++;
            retryAllowedAt = DateTimeOffset.Now.Add(cooldown);
            store.Save(retryAllowedAt.Value, failureCount, fingerprint);
        }
    }

    public void Clear()
    {
        lock (gate)
        {
            EnsureLoaded();
            Reset();
        }
    }

    private void Reset()
    {
        failureCount = 0;
        retryAllowedAt = null;
        fingerprint = null;
        store.Clear();
    }
}

/// <summary>
/// Persists the Claude usage endpoint's 429 cooldown across app restarts. The
/// <c>/api/oauth/usage</c> rate limit is enforced per account and shared with
/// everything using the same OAuth token, so keeping the cooldown only in memory
/// meant a relaunch during a cooldown immediately re-fired a still-rate-limited
/// request. Persisting the retry instant lets a restarted app honor it instead.
/// </summary>
internal sealed class ClaudeRateLimitStore
{
    private readonly string path;

    public ClaudeRateLimitStore(string path)
    {
        this.path = path;
    }

    // Returns the persisted cooldown only while its retry instant is still in the
    // future; an expired or missing record reads as null.
    public ClaudeRateLimitSnapshot? Load()
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }

            var record = JsonSerializer.Deserialize<Record>(File.ReadAllText(path));
            if (record is null || record.RetryAllowedAt <= DateTimeOffset.Now)
            {
                return null;
            }

            return new ClaudeRateLimitSnapshot(
                record.RetryAllowedAt,
                Math.Max(0, record.FailureCount),
                record.Fingerprint);
        }
        catch
        {
            return null;
        }
    }

    public void Save(DateTimeOffset retryAllowedAt, int failureCount, string? fingerprint)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonSerializer.Serialize(new Record(retryAllowedAt, failureCount, fingerprint)));
        }
        catch
        {
        }
    }

    public void Clear()
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    // FailureCount and Fingerprint are optional so a legacy record written before
    // those were persisted still deserializes; a record with no fingerprint is
    // unattributable and is dropped on the next check rather than applied to
    // whatever credentials happen to be current.
    private sealed record Record(DateTimeOffset RetryAllowedAt, int FailureCount = 0, string? Fingerprint = null);
}

/// <summary>A persisted 429 cooldown: when the app may retry, and how many
/// consecutive failures preceded it so exponential backoff survives a restart.</summary>
internal readonly record struct ClaudeRateLimitSnapshot(
    DateTimeOffset RetryAllowedAt,
    int FailureCount,
    string? Fingerprint);
