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

    /// Which window the percentage comes from. DisplayPercent reads its number
    /// from here so the countdown shown beside it always names the reset that
    /// number is actually counting down to, rather than the two drifting apart.
    public static ForecastWindow? DisplayWindow(ProviderUsage usage)
    {
        if (usage.RemainingPercent7d is <= 10)
        {
            return ForecastWindow.SevenDay;
        }

        if (usage.RemainingPercent5h is not null)
        {
            return ForecastWindow.FiveHour;
        }

        return usage.RemainingPercent7d is not null ? ForecastWindow.SevenDay : null;
    }

    public static int? DisplayPercent(ProviderUsage usage) => DisplayWindow(usage) switch
    {
        ForecastWindow.FiveHour => usage.RemainingPercent5h,
        ForecastWindow.SevenDay => usage.RemainingPercent7d,
        _ => null
    };

    public static DateTimeOffset? DisplayResetAt(ProviderUsage usage) => DisplayWindow(usage) switch
    {
        ForecastWindow.FiveHour => usage.ResetAt5h,
        ForecastWindow.SevenDay => usage.ResetAt7d,
        _ => null
    };

    /// Warning emphasis is reserved for an actually low 7d window. Showing the
    /// 7d number merely because the 5h window is absent (the normal Codex state
    /// since OpenAI removed the 5h limit) must not read as a warning.
    public static bool IsSevenDayWarning(ProviderUsage usage) =>
        usage.RemainingPercent7d is <= 10;

    /// Which window the forecast and sparkline surfaces should use: the 5h
    /// window when it reports, otherwise the 7d window (Codex's normal state
    /// since OpenAI removed the 5h limit — without the fallback Codex would
    /// have no forecast or sparkline at all).
    public static ForecastWindow PreferredForecastWindow(ProviderUsage usage)
    {
        if (usage.RemainingPercent5h is not null)
        {
            return ForecastWindow.FiveHour;
        }

        return usage.RemainingPercent7d is not null ? ForecastWindow.SevenDay : ForecastWindow.FiveHour;
    }

    public static string ProviderLabel(Provider provider, ProviderLabelStyle style) =>
        style == ProviderLabelStyle.Abbreviation
            ? provider == Provider.Codex ? "Cdx" : "Cl"
            : provider == Provider.Codex ? "Codex" : "Claude";

    public static string FormatPercent(int? value) => value is null ? "--" : $"{value}%";

    public static string FormatReset(DateTimeOffset? date, Localizer localizer)
    {
        if (date is null)
        {
            return "--";
        }

        var remaining = date.Value - DateTimeOffset.Now;
        if (remaining <= TimeSpan.Zero)
        {
            return localizer.Text(L10nKey.Now);
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

    /// The menu's reset text for one window. A window that reports a balance but
    /// no reset instant is not a failed reading: Claude opens its 5h window on
    /// first use, so until then there is no reset to name. Saying that beats
    /// "--", which reads as "we could not get it".
    ///
    /// With no balance for this window there are still two cases. If the provider
    /// answered with its other window (providerReported), the read worked and
    /// this window simply was not in it — Claude Ultra drops the 5h window for
    /// verified accounts — so say that. Only when nothing came back at all is
    /// there nothing to claim, and the placeholder stays.
    public static string FormatWindowReset(
        int? remainingPercent,
        DateTimeOffset? resetAt,
        Localizer localizer,
        bool providerReported = false)
    {
        if (resetAt is not null)
        {
            return FormatReset(resetAt, localizer);
        }

        if (remainingPercent is not null)
        {
            return localizer.Text(L10nKey.WindowNotOpen);
        }

        if (providerReported)
        {
            return localizer.Text(L10nKey.WindowNotReported);
        }

        return "--";
    }

    /// Tooltip variant of FormatReset: the same buckets without the inner space,
    /// because the tooltip is trimmed to what the shell will show. Returns null
    /// rather than "--" when there is no reset, so the caller appends nothing.
    public static string? FormatResetCompact(DateTimeOffset? date, Localizer localizer)
    {
        if (date is null)
        {
            return null;
        }

        var remaining = date.Value - DateTimeOffset.Now;
        if (remaining <= TimeSpan.Zero)
        {
            return localizer.Text(L10nKey.Now);
        }

        if (remaining.TotalHours < 1)
        {
            return $"{Math.Max(0, (int)remaining.TotalMinutes)}m";
        }

        if (remaining.TotalDays < 1)
        {
            return $"{(int)remaining.TotalHours}h{remaining.Minutes}m";
        }

        return $"{(int)remaining.TotalDays}d{remaining.Hours}h";
    }

    /// The countdown suffix for a provider's tooltip segment: a leading space plus
    /// the compact time, or an empty string when the countdown is off, the window
    /// is unknown, or the provider reported no reset instant.
    public static string ResetCountdownSuffix(
        ProviderUsage? usage,
        bool showResetCountdown,
        Localizer localizer)
    {
        if (!showResetCountdown || usage is null)
        {
            return string.Empty;
        }

        // A cached reading's reset instant keeps ticking down while the value
        // behind it stands still, and once it passes the countdown reads "now" for
        // as long as the fallback lasts. Show no time rather than a wrong one. A
        // status-line reading is a measurement with a live window: it is only
        // reported while it is fresh, and a window whose reset has passed is
        // dropped on the way in.
        if (usage.Source != UsageSource.Api && usage.Source != UsageSource.StatusLine)
        {
            return string.Empty;
        }

        var text = FormatResetCompact(DisplayResetAt(usage), localizer);
        if (text is null)
        {
            return string.Empty;
        }

        return " " + text;
    }

    public static string Tooltip(
        UsageSnapshot? snapshot,
        ProviderLabelStyle labelStyle = ProviderLabelStyle.Icon,
        bool showResetCountdown = false,
        Localizer? localizer = null)
    {
        if (snapshot is null)
        {
            return "Token Tracker: loading";
        }

        localizer ??= new Localizer(AppLanguage.English);
        var codexCountdown = ResetCountdownSuffix(snapshot.Codex, showResetCountdown, localizer);
        var claudeCountdown = ResetCountdownSuffix(snapshot.Claude, showResetCountdown, localizer);
        return $"{ProviderLabel(Provider.Codex, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Codex))}{codexCountdown}, {ProviderLabel(Provider.Claude, labelStyle)} {FormatPercent(DisplayPercent(snapshot.Claude))}{claudeCountdown}";
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

    public static bool TrayIconShowsWarning(UsageSnapshot? snapshot, DisplayMode mode)
    {
        if (snapshot is null)
        {
            return false;
        }

        return mode switch
        {
            DisplayMode.CodexOnly => IsSevenDayWarning(snapshot.Codex),
            DisplayMode.ClaudeOnly => IsSevenDayWarning(snapshot.Claude),
            _ => AnyLowestUsageShowsWarning(snapshot, mode)
        };
    }

    private static bool AnyLowestUsageShowsWarning(UsageSnapshot snapshot, DisplayMode mode)
    {
        var trayPercent = TrayIconPercent(snapshot, mode);
        return new[] { snapshot.Codex, snapshot.Claude }
            .Any(usage => DisplayPercent(usage) == trayPercent && IsSevenDayWarning(usage));
    }

    private static string FormatLowest(UsageSnapshot snapshot)
    {
        var lowest = new[] { DisplayPercent(snapshot.Claude), DisplayPercent(snapshot.Codex) }
            .Where(value => value is not null)
            .Min();

        return lowest is null ? "AI --" : $"AI {lowest}%";
    }
}
