using System.Globalization;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

// Money spent on Claude and Codex beyond what the subscription windows show. See
// docs/cost-display-design.md. Mirrors Sources/TokenTrackerCore/Cost.swift.

/// An amount of money. <c>decimal</c>, never <c>double</c>: Anthropic reports cents
/// as decimal strings, and adding up a month of hourly buckets in binary floating
/// point drifts by whole cents.
public sealed record CostAmount
{
    public CostAmount(decimal value, string currency = "USD")
    {
        Value = value;
        Currency = currency.ToUpperInvariant();
    }

    public decimal Value { get; }

    /// Upper-case ISO 4217 code. Both providers bill in USD.
    public string Currency { get; }
}

/// One slice of the month's spend, such as a model.
public sealed record CostLineItem(string Name, CostAmount Amount)
{
    /// The largest items, after adding up those that share a name across pages.
    public static IReadOnlyList<CostLineItem> Top(IEnumerable<CostLineItem> items, int limit = 3) =>
        items
            .GroupBy(item => item.Name, StringComparer.Ordinal)
            .Select(group => new CostLineItem(
                group.Key,
                new CostAmount(group.Sum(item => item.Amount.Value), group.Last().Amount.Currency)))
            .Where(item => item.Amount.Value > 0)
            .OrderByDescending(item => item.Amount.Value)
            .ThenBy(item => item.Name, StringComparer.Ordinal)
            .Take(limit)
            .ToList();
}

public enum CostFreshnessKind
{
    /// Cost appears within minutes, with no cut-off to report (OpenAI).
    Live,

    /// Complete up to <see cref="CostFreshness.RefreshedAt"/>; usage after it is
    /// missing or partial (Anthropic's <c>data_refreshed_at</c>).
    RefreshedAt,

    /// Nothing is tallied yet for the requested range.
    NotTallied
}

/// How far a provider's cost data reaches.
public sealed record CostFreshness(CostFreshnessKind Kind, DateTimeOffset? RefreshedAt = null)
{
    public static CostFreshness Live { get; } = new(CostFreshnessKind.Live);
    public static CostFreshness NotTallied { get; } = new(CostFreshnessKind.NotTallied);
    public static CostFreshness At(DateTimeOffset refreshedAt) => new(CostFreshnessKind.RefreshedAt, refreshedAt);
}

/// One time bucket of cost, as the provider cut it.
public sealed record CostBucket(DateTimeOffset Start, DateTimeOffset End, CostAmount Amount);

/// One page of a cost response.
public sealed record CostPage(
    IReadOnlyList<CostBucket> Buckets,
    IReadOnlyList<CostLineItem> Items,
    string? NextPage,
    CostFreshness Freshness);

/// This month's spend for one provider, in the device's time zone.
/// <param name="MonthToDate">From local midnight on the 1st. Null while nothing is tallied.</param>
/// <param name="Today">From local midnight today. Null while today is not tallied
/// yet, or when the provider's day buckets do not start at local midnight, so
/// today cannot be told apart from yesterday.</param>
public sealed record CostReport(CostAmount? MonthToDate, CostAmount? Today, CostFreshness Freshness);

/// "Today" and "this month" in the device's time zone. Never a fixed zone: the
/// user is wherever their PC says they are. Calendar arithmetic, not "midnight +
/// 24h", so days of 23 or 25 hours around a DST change come out right.
public static class CostPeriod
{
    public static DateTimeOffset DayStart(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        var local = TimeZoneInfo.ConvertTime(now, timeZone);
        return LocalMidnight(local.Date, timeZone);
    }

    public static DateTimeOffset MonthStart(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        var local = TimeZoneInfo.ConvertTime(now, timeZone);
        return LocalMidnight(new DateTime(local.Year, local.Month, 1), timeZone);
    }

    /// What one fetch asks for: the 1st at local midnight up to now. A month is at
    /// most 31 days, within the Analytics API's limit for one request.
    public static (DateTimeOffset Start, DateTimeOffset End) RequestRange(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        var start = MonthStart(now, timeZone);
        return (start, now > start ? now : start);
    }

    /// <c>2026-11</c>, for keys that last one local month.
    public static string MonthKey(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        var local = TimeZoneInfo.ConvertTime(now, timeZone);
        return local.Year.ToString("0000", CultureInfo.InvariantCulture) + "-" +
            local.Month.ToString("00", CultureInfo.InvariantCulture);
    }

    /// The first instant of a local calendar day. A zone that springs forward at
    /// midnight has no 00:00 that day, so the day starts at its first valid minute;
    /// a zone that falls back across midnight has two, and the earlier one counts.
    private static DateTimeOffset LocalMidnight(DateTime date, TimeZoneInfo timeZone)
    {
        var local = DateTime.SpecifyKind(date.Date, DateTimeKind.Unspecified);
        for (var minutes = 0; minutes < 180 && timeZone.IsInvalidTime(local); minutes++)
        {
            local = local.AddMinutes(1);
        }

        var offset = timeZone.IsAmbiguousTime(local)
            ? timeZone.GetAmbiguousTimeOffsets(local).Max()
            : timeZone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset);
    }
}

public static class CostAggregator
{
    /// A bucket that starts this much before local midnight still counts toward the
    /// new day. Anthropic rounds hourly buckets down to the hour, so a zone half or
    /// three quarters of an hour off UTC gets its day boundary up to 45 minutes
    /// early; a day bucket that starts at UTC midnight is hours off and does not.
    public static readonly TimeSpan BoundaryTolerance = TimeSpan.FromHours(1);

    /// Adds up the buckets that overlap this month and today, in <paramref name="timeZone"/>.
    public static CostReport Report(
        IReadOnlyList<CostBucket> buckets,
        CostFreshness freshness,
        DateTimeOffset now,
        TimeZoneInfo timeZone)
    {
        if (freshness.Kind == CostFreshnessKind.NotTallied)
        {
            return new CostReport(null, null, freshness);
        }

        var monthStart = CostPeriod.MonthStart(now, timeZone);
        var dayStart = CostPeriod.DayStart(now, timeZone);
        var currency = buckets.Count > 0 ? buckets[0].Amount.Currency : "USD";

        // A watermark from before the 1st covers none of this month: not tallied,
        // rather than a month of nothing.
        var monthTallied = freshness.Kind != CostFreshnessKind.RefreshedAt || freshness.RefreshedAt > monthStart;
        var monthToDate = monthTallied
            ? new CostAmount(
                buckets.Where(bucket => Overlaps(bucket, monthStart, now)).Sum(bucket => bucket.Amount.Value),
                currency)
            : null;

        var todays = buckets.Where(bucket => Overlaps(bucket, dayStart, now)).ToList();
        var straddles = todays.Any(bucket => dayStart - bucket.Start > BoundaryTolerance);
        var tallied = freshness.Kind != CostFreshnessKind.RefreshedAt || freshness.RefreshedAt > dayStart;
        var today = tallied && !straddles
            ? new CostAmount(todays.Sum(bucket => bucket.Amount.Value), currency)
            : null;
        return new CostReport(monthToDate, today, freshness);
    }

    private static bool Overlaps(CostBucket bucket, DateTimeOffset start, DateTimeOffset end) =>
        bucket.End > start && bucket.Start < end;
}

/// <c>GET /v1/organizations/analytics/cost</c> (Analytics API, beta). Amounts are
/// cents as decimal strings with six places: <c>"41280.000000"</c> is $412.80.
///
/// Two requests feed a report: hourly buckets for the totals, and one grouped by
/// <c>model</c> without buckets for the split. The second returns one row per
/// model spanning the whole range, so take its items and not its buckets.
public static class AnthropicCostParser
{
    public static CostPage? Page(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("data", out var rows) ||
                rows.ValueKind != JsonValueKind.Array)
            {
                return null;
            }

            var buckets = new List<CostBucket>();
            var items = new List<CostLineItem>();
            foreach (var row in rows.EnumerateArray())
            {
                if (row.ValueKind != JsonValueKind.Object ||
                    !row.TryGetProperty("cost", out var cost) ||
                    cost.ValueKind != JsonValueKind.Object ||
                    CostJson.Decimal(cost, "amount") is not { } cents)
                {
                    continue;
                }

                var amount = new CostAmount(cents / 100m, CostJson.String(cost, "currency") ?? "USD");
                if (CostJson.Date(row, "starting_at") is { } start && CostJson.Date(row, "ending_at") is { } end)
                {
                    buckets.Add(new CostBucket(start, end, amount));
                }

                if (row.TryGetProperty("group", out var group) &&
                    group.ValueKind == JsonValueKind.Object &&
                    CostJson.String(group, "model") is { Length: > 0 } model)
                {
                    items.Add(new CostLineItem(model, amount));
                }
            }

            var freshness = CostJson.Date(root, "data_refreshed_at") is { } refreshed
                ? CostFreshness.At(refreshed)
                : CostFreshness.NotTallied;
            return new CostPage(buckets, items, CostJson.NextPage(root), freshness);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <c>GET /v1/organization/costs</c>. Amounts are dollars as numbers. The published
/// schema names the bucket's list <c>result</c> while its example response says
/// <c>results</c>, so both are read.
public static class OpenAICostParser
{
    public static CostPage? Page(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("data", out var rows) ||
                rows.ValueKind != JsonValueKind.Array)
            {
                return null;
            }

            var buckets = new List<CostBucket>();
            var items = new List<CostLineItem>();
            foreach (var row in rows.EnumerateArray())
            {
                if (row.ValueKind != JsonValueKind.Object ||
                    CostJson.UnixSeconds(row, "start_time") is not { } start ||
                    CostJson.UnixSeconds(row, "end_time") is not { } end)
                {
                    continue;
                }

                var total = 0m;
                var currency = "USD";
                foreach (var name in new[] { "results", "result" })
                {
                    if (!row.TryGetProperty(name, out var results) || results.ValueKind != JsonValueKind.Array)
                    {
                        continue;
                    }

                    foreach (var result in results.EnumerateArray())
                    {
                        if (result.ValueKind != JsonValueKind.Object ||
                            !result.TryGetProperty("amount", out var money) ||
                            money.ValueKind != JsonValueKind.Object ||
                            CostJson.Decimal(money, "value") is not { } value)
                        {
                            continue;
                        }

                        currency = CostJson.String(money, "currency")?.ToUpperInvariant() ?? currency;
                        total += value;
                        if (CostJson.String(result, "line_item") is { Length: > 0 } item)
                        {
                            items.Add(new CostLineItem(item, new CostAmount(value, currency)));
                        }
                    }

                    break;
                }

                buckets.Add(new CostBucket(start, end, new CostAmount(total, currency)));
            }

            return new CostPage(buckets, items, CostJson.NextPage(root), CostFreshness.Live);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// Claude extra usage: what the account has spent past its plan limits.
/// <param name="Severity">The provider's own word for how close the limit is, such as <c>normal</c>.</param>
public sealed record ClaudeExtraUsage(CostAmount Used, CostAmount? Limit, string? Severity);

/// Money the subscription usage responses already carry. Each reading is null
/// unless the account actually pays this way, which is what keeps money off the
/// screen of a subscription-only user. A missing or unexpected field reads as off.
public static class SubscriptionCostParser
{
    /// From <c>GET /api/oauth/usage</c>. Extra usage counts as on when either
    /// <c>spend</c> or <c>extra_usage</c> says so; the amount comes from
    /// <c>spend.used</c>, the one field that states its own unit.
    public static ClaudeExtraUsage? ClaudeExtra(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            var hasSpend = root.TryGetProperty("spend", out var spend) && spend.ValueKind == JsonValueKind.Object;
            var hasExtra = root.TryGetProperty("extra_usage", out var extra) && extra.ValueKind == JsonValueKind.Object;
            var enabled = (hasSpend && CostJson.IsTrue(spend, "enabled")) || (hasExtra && CostJson.IsTrue(extra, "is_enabled"));
            if (!enabled || !hasSpend || MinorUnits(spend, "used") is not { } used)
            {
                return null;
            }

            return new ClaudeExtraUsage(used, MinorUnits(spend, "limit"), CostJson.String(spend, "severity"));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// From <c>GET /backend-api/wham/usage</c>: the credit balance, in credits rather
    /// than dollars. Null for an account without credits.
    public static decimal? CodexCredits(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("credits", out var credits) ||
                credits.ValueKind != JsonValueKind.Object ||
                !CostJson.IsTrue(credits, "has_credits"))
            {
                return null;
            }

            return CostJson.Decimal(credits, "balance");
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <c>{ "amount_minor": 186, "currency": "USD", "exponent": 2 }</c> is $1.86.
    private static CostAmount? MinorUnits(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var money) ||
            money.ValueKind != JsonValueKind.Object ||
            CostJson.Decimal(money, "amount_minor") is not { } minor ||
            !money.TryGetProperty("exponent", out var exponentElement) ||
            exponentElement.ValueKind != JsonValueKind.Number ||
            !exponentElement.TryGetInt32(out var exponent) ||
            exponent is < 0 or > 6)
        {
            return null;
        }

        var divisor = 1m;
        for (var place = 0; place < exponent; place++)
        {
            divisor *= 10m;
        }

        return new CostAmount(minor / divisor, CostJson.String(money, "currency") ?? "USD");
    }
}

/// One line of money on a provider's card or submenu, from what its subscription
/// usage response carried.
/// <param name="Value"><c>$1.86 / $5.00</c>, <c>$1.86</c> without a limit, or a credit balance such as <c>18.40</c>.</param>
/// <param name="Percent">Whole percent of the extra usage limit spent, for a bar. Null without a limit.</param>
public sealed record SubscriptionCostLine(string Label, string Value, int? Percent);

public static class SubscriptionCostText
{
    /// Null unless the account pays past its plan, so a subscription-only submenu
    /// stays exactly as it was.
    public static SubscriptionCostLine? Line(ProviderUsage usage, Localizer localizer)
    {
        if (usage.ExtraUsage is { } extra)
        {
            var value = CostFormatter.Text(extra.Used);
            int? percent = null;
            if (extra.Limit is { } limit && limit.Currency == extra.Used.Currency)
            {
                value += " / " + CostFormatter.Text(limit);
                percent = CostBudget.Percent(extra.Used.Value, limit.Value);
            }

            return new SubscriptionCostLine(localizer.Text(L10nKey.CostExtraUsage), value, percent);
        }

        if (usage.CreditBalance is { } balance)
        {
            return new SubscriptionCostLine(localizer.Text(L10nKey.CostCreditBalance), CostFormatter.Credits(balance), null);
        }

        return null;
    }
}

/// Whether a provider gets any money on screen: popup, menu, tray or alert. Every
/// one of them asks this, so a subscription-only user with extra usage off sees
/// no trace of the feature.
public static class CostVisibility
{
    public static bool Shows(bool subscriptionExtra, bool apiCostEnabled, bool hasAdminKey) =>
        subscriptionExtra || (apiCostEnabled && hasAdminKey);

    /// The tray keeps showing percentages while subscription limits are shown; only
    /// a provider tracked by API cost alone puts its month's spend there.
    public static bool MenuBarShowsCost(bool subscriptionLimitsShown, bool apiCostShown) =>
        !subscriptionLimitsShown && apiCostShown;
}

public static class CostFormatter
{
    /// <c>$12.34</c>, <c>$1.2K</c>, <c>$3.4M</c>, <c>&lt;$0.01</c>; other currencies as
    /// <c>12.34 EUR</c>. Rounds half away from zero, the same on both ports.
    public static string Text(CostAmount amount)
    {
        var magnitude = Math.Abs(amount.Value);
        var sign = amount.Value < 0 ? "-" : "";
        string number;
        if (magnitude >= 1_000_000m)
        {
            number = Fixed(magnitude / 1_000_000m, 1) + "M";
        }
        else if (magnitude >= 1000m)
        {
            number = Fixed(magnitude / 1000m, 1) + "K";
        }
        else if (magnitude > 0m && magnitude < 0.01m)
        {
            return amount.Currency == "USD" ? "<$0.01" : "<0.01 " + amount.Currency;
        }
        else
        {
            number = Fixed(magnitude, 2);
        }

        return amount.Currency == "USD" ? sign + "$" + number : sign + number + " " + amount.Currency;
    }

    /// The tray's short form: whole dollars from $10 (<c>$42</c>), cents below that so
    /// a small spend does not read as <c>$0</c> (<c>$3.07</c>), and <c>$1.2K</c> from a thousand.
    public static string Compact(CostAmount amount)
    {
        var magnitude = Math.Abs(amount.Value);
        if (magnitude < 10m || magnitude >= 1000m)
        {
            return Text(amount);
        }

        var sign = amount.Value < 0 ? "-" : "";
        var number = decimal.Round(magnitude, 0, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture);
        return amount.Currency == "USD" ? sign + "$" + number : sign + number + " " + amount.Currency;
    }

    /// A credit balance, which is not money: <c>18.40</c>.
    public static string Credits(decimal value) => Fixed(value, 2);

    private static string Fixed(decimal value, int places) =>
        decimal.Round(value, places, MidpointRounding.AwayFromZero)
            .ToString(places == 1 ? "0.0" : "0.00", CultureInfo.InvariantCulture);
}

/// A monthly budget, in the provider's currency. Zero is off.
public static class CostBudget
{
    public static IReadOnlyList<int> Thresholds { get; } = new[] { 80, 100 };

    /// Whole percent of the budget spent, rounded down. Null with no budget.
    public static int? Percent(decimal spent, decimal budget) =>
        budget > 0m ? (int)decimal.Floor(spent * 100m / budget) : null;

    /// The thresholds this month's spend has reached.
    public static IReadOnlyList<int> ReachedThresholds(decimal spent, decimal budget)
    {
        if (Percent(spent, budget) is not { } percent)
        {
            return Array.Empty<int>();
        }

        return Thresholds.Where(threshold => percent >= threshold).ToList();
    }

    /// One alert per threshold per local month: <c>claude-cost-80-2026-11</c>.
    public static string AlertId(Provider provider, int threshold, DateTimeOffset now, TimeZoneInfo timeZone) =>
        provider.ToId() + "-cost-" + threshold.ToString(CultureInfo.InvariantCulture) + "-" + CostPeriod.MonthKey(now, timeZone);
}

/// When to ask an Admin API again. Anthropic's Analytics data moves every few
/// hours, and its 60 requests a minute are shared by everything the organization
/// runs against the API, so ten minutes loses nothing.
public static class CostFetchPolicy
{
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(10);
    public static readonly TimeSpan RetryInterval = TimeSpan.FromMinutes(5);

    public static DateTimeOffset NextFetch(DateTimeOffset attemptAt, bool succeeded) =>
        attemptAt + (succeeded ? Interval : RetryInterval);

    /// No fetch yet is due at once.
    public static bool IsDue(DateTimeOffset? nextFetchAt, DateTimeOffset now) =>
        nextFetchAt is not { } next || now >= next;
}

internal static class CostJson
{
    /// A JSON number or numeric string as an exact decimal, read from its text.
    public static decimal? Decimal(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetDecimal(out var number) => number,
            JsonValueKind.String when decimal.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) => number,
            _ => null
        };
    }

    public static string? String(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    public static bool IsTrue(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    public static DateTimeOffset? Date(JsonElement parent, string name) =>
        String(parent, name) is { } text &&
        DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : null;

    public static DateTimeOffset? UnixSeconds(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var seconds)
            ? DateTimeOffset.FromUnixTimeSeconds(seconds)
            : null;

    public static string? NextPage(JsonElement root) =>
        root.TryGetProperty("has_more", out var hasMore) && hasMore.ValueKind == JsonValueKind.True
            ? String(root, "next_page")
            : null;
}
