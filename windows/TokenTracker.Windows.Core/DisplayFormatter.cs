namespace TokenTracker.Windows.Core;

public static class DisplayFormatter
{
    public static string StatusTitle(UsageSnapshot? snapshot, DisplayMode mode, ProviderLabelStyle labelStyle = ProviderLabelStyle.Abbreviation)
    {
        if (snapshot is null)
        {
            return "AI --";
        }

        return mode switch
        {
            DisplayMode.LowestRemaining => FormatLowest(snapshot),
            DisplayMode.Both => $"{ProviderLabel(Provider.Codex, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Codex))} · {ProviderLabel(Provider.Claude, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Claude))}",
            DisplayMode.CodexOnly => $"{ProviderLabel(Provider.Codex, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Codex))}",
            DisplayMode.ClaudeOnly => $"{ProviderLabel(Provider.Claude, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Claude))}",
            _ => "AI --"
        };
    }

    public static string DetailLine(ProviderUsage usage) =>
        $"{usage.DisplayName}: 5h {FormatPercent(usage.RemainingPercent5h)}, 7d {FormatPercent(usage.RemainingPercent7d)}";

    public static int? DisplayPercent(ProviderUsage usage)
    {
        if (usage.RemainingPercent7d is <= 10)
        {
            return usage.RemainingPercent7d;
        }

        return usage.RemainingPercent5h ?? usage.RemainingPercent7d;
    }

    public static bool DisplaysSevenDayPercent(ProviderUsage usage) =>
        usage.RemainingPercent7d is not null && (usage.RemainingPercent7d <= 10 || usage.RemainingPercent5h is null);

    public static string ProviderLabel(Provider provider, ProviderLabelStyle style) =>
        style == ProviderLabelStyle.Abbreviation
            ? provider == Provider.Codex ? "Cdx" : "Cl"
            : provider == Provider.Codex ? "Codex" : "Claude";

    public static string FormatPercent(int? value) => value is null ? "--" : $"{value}%";

    public static string FormatReset(DateTimeOffset? date)
    {
        if (date is null)
        {
            return "--";
        }

        var remaining = date.Value - DateTimeOffset.Now;
        if (remaining <= TimeSpan.Zero)
        {
            return "now";
        }

        if (remaining.TotalHours < 1)
        {
            return $"{Math.Max(0, (int)remaining.TotalMinutes)}m";
        }

        if (remaining.TotalDays < 1)
        {
            return $"{(int)remaining.TotalHours}h {remaining.Minutes}m";
        }

        return $"{(int)remaining.TotalDays}d {remaining.Hours}h";
    }

    public static string Tooltip(UsageSnapshot? snapshot, ProviderLabelStyle labelStyle = ProviderLabelStyle.Icon)
    {
        if (snapshot is null)
        {
            return "Token Tracker: loading";
        }

        return $"{ProviderLabel(Provider.Codex, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Codex))}, {ProviderLabel(Provider.Claude, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Claude))}";
    }

    public static int? TrayIconPercent(UsageSnapshot? snapshot, DisplayMode mode)
    {
        if (snapshot is null)
        {
            return null;
        }

        return mode switch
        {
            DisplayMode.CodexOnly => DisplayPercent(snapshot.Codex),
            DisplayMode.ClaudeOnly => DisplayPercent(snapshot.Claude),
            _ => new[] { DisplayPercent(snapshot.Codex), DisplayPercent(snapshot.Claude) }
                .Where(value => value is not null)
                .Min()
        };
    }

    public static bool TrayIconUsesSevenDay(UsageSnapshot? snapshot, DisplayMode mode)
    {
        if (snapshot is null)
        {
            return false;
        }

        return mode switch
        {
            DisplayMode.CodexOnly => DisplaysSevenDayPercent(snapshot.Codex),
            DisplayMode.ClaudeOnly => DisplaysSevenDayPercent(snapshot.Claude),
            _ => AnyLowestUsageUsesSevenDay(snapshot, mode)
        };
    }

    private static bool AnyLowestUsageUsesSevenDay(UsageSnapshot snapshot, DisplayMode mode)
    {
        var trayPercent = TrayIconPercent(snapshot, mode);
        return new[] { snapshot.Codex, snapshot.Claude }
            .Any(usage => DisplayPercent(usage) == trayPercent && DisplaysSevenDayPercent(usage));
    }

    private static string FormatLowest(UsageSnapshot snapshot)
    {
        var lowest = new[] { DisplayPercent(snapshot.Claude), DisplayPercent(snapshot.Codex) }
            .Where(value => value is not null)
            .Min();

        return lowest is null ? "AI --" : $"AI {lowest}%";
    }
}
