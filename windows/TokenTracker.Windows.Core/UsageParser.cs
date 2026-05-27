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

        return new ProviderUsage(
            Provider.Codex,
            PercentMath.RemainingPercent(TryGetDouble(primary, "used_percent")),
            PercentMath.RemainingPercent(TryGetDouble(secondary, "used_percent")),
            TryGetUnixTime(primary, "reset_at"),
            TryGetUnixTime(secondary, "reset_at"),
            UsageSource.Api,
            null,
            TryGetString(root, "plan_type"),
            null,
            updatedAt ?? DateTimeOffset.Now);
    }

    public static ProviderUsage ParseClaudeUsage(string json, DateTimeOffset? updatedAt = null)
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
            null,
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
