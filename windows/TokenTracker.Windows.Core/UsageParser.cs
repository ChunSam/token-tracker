using System.Globalization;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

public static class UsageParser
{
    public static ProviderUsage ParseCodexUsage(string json, DateTimeOffset? updatedAt = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var rateLimit = root.GetProperty("rate_limit");

        TryGetObject(rateLimit, "primary_window", out var primary);
        TryGetObject(rateLimit, "secondary_window", out var secondary);
        var mapped = CodexWindowMapper.Map(ToCodexWindow(primary), ToCodexWindow(secondary));

        return new ProviderUsage(
            Provider.Codex,
            PercentMath.RemainingPercent(mapped.FiveHour?.UsedPercent),
            PercentMath.RemainingPercent(mapped.SevenDay?.UsedPercent),
            mapped.FiveHour?.ResetAt,
            mapped.SevenDay?.ResetAt,
            UsageSource.Api,
            null,
            TryGetString(root, "plan_type"),
            null,
            updatedAt ?? DateTimeOffset.Now);
    }

    private static CodexRateWindow? ToCodexWindow(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        return new CodexRateWindow(
            TryGetDouble(element, "used_percent"),
            TryGetUnixTime(element, "reset_at"),
            TryGetDouble(element, "limit_window_seconds"));
    }

    public static ProviderUsage ParseClaudeUsage(string json, DateTimeOffset? updatedAt = null, string? fallbackPlan = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        TryGetObject(root, "five_hour", out var fiveHour);
        TryGetObject(root, "seven_day", out var sevenDay);

        return new ProviderUsage(
            Provider.Claude,
            PercentMath.RemainingPercent(TryGetDouble(fiveHour, "utilization")),
            PercentMath.RemainingPercent(TryGetDouble(sevenDay, "utilization")),
            TryGetIsoDate(fiveHour, "resets_at"),
            TryGetIsoDate(sevenDay, "resets_at"),
            UsageSource.Api,
            null,
            ReadPlan(root) ?? fallbackPlan,
            null,
            updatedAt ?? DateTimeOffset.Now);
    }

    private static bool TryGetObject(JsonElement element, string name, out JsonElement value)
    {
        value = default;
        return element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(name, out value)
            && value.ValueKind == JsonValueKind.Object;
    }

    private static double? TryGetDouble(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(name, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetDouble(out var number) => number,
            JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) => number,
            _ => null
        };
    }

    private static string? TryGetString(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(name, out var value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    }

    private static string? ReadPlan(JsonElement element)
    {
        foreach (var key in new[] { "plan_type", "planType", "subscription_type", "subscriptionType", "tier", "rate_limit_tier", "rateLimitTier" })
        {
            var value = TryGetString(element, key);
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return null;
    }

    private static DateTimeOffset? TryGetUnixTime(JsonElement element, string name)
    {
        var value = TryGetDouble(element, name);
        return value is null ? null : DateTimeOffset.FromUnixTimeSeconds((long)value.Value);
    }

    private static DateTimeOffset? TryGetIsoDate(JsonElement element, string name)
    {
        var value = TryGetString(element, name);
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : null;
    }
}
