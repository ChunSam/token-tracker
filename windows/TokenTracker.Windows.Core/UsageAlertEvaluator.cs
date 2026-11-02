namespace TokenTracker.Windows.Core;

public sealed record UsageAlertSettings
{
    public UsageAlertSettings(
        bool notificationsEnabled,
        int fiveHourThreshold,
        int sevenDayThreshold,
        int resetWarningMinutes,
        TimeSpan? stalledAfter = null)
    {
        NotificationsEnabled = notificationsEnabled;
        FiveHourThreshold = Math.Clamp(fiveHourThreshold, 0, 100);
        SevenDayThreshold = Math.Clamp(sevenDayThreshold, 0, 100);
        ResetWarningMinutes = Math.Max(0, resetWarningMinutes);
        var stalled = stalledAfter ?? TimeSpan.Zero;
        StalledAfter = stalled > TimeSpan.Zero ? stalled : TimeSpan.Zero;
    }

    public bool NotificationsEnabled { get; }
    public int FiveHourThreshold { get; }
    public int SevenDayThreshold { get; }
    public int ResetWarningMinutes { get; }

    /// How long a cached reading may stand before it is reported as stalled.
    /// Zero disables the alert, matching the other thresholds here.
    public TimeSpan StalledAfter { get; }
}

public sealed record UsageAlertCandidate(string Id, string Title, string Body);

public static class UsageAlertEvaluator
{
    public static IReadOnlyList<UsageAlertCandidate> Candidates(
        UsageSnapshot snapshot,
        UsageAlertSettings settings,
        DateTimeOffset? now = null,
        Localizer? localizer = null)
    {
        if (!settings.NotificationsEnabled)
        {
            return Array.Empty<UsageAlertCandidate>();
        }

        localizer ??= new Localizer(AppLanguage.English);
        var current = now ?? DateTimeOffset.Now;
        return new[]
            {
                snapshot.Usage(Provider.Claude),
                snapshot.Usage(Provider.Codex)
            }
            .SelectMany(usage => Candidates(usage, settings, current, localizer))
            .ToArray();
    }

    private static IEnumerable<UsageAlertCandidate> Candidates(
        ProviderUsage usage,
        UsageAlertSettings settings,
        DateTimeOffset now,
        Localizer localizer)
    {
        if (!usage.IsAvailable)
        {
            yield break;
        }

        // First, because it says how much the numbers below it are still worth.
        var stalled = StalledAlert(usage, settings, now, localizer);
        if (stalled is not null)
        {
            yield return stalled;
        }

        // The low-balance bodies are symbols only, so they read the same in every
        // language and skip the localizer.
        if (usage.RemainingPercent5h is { } fiveHourRemaining &&
            settings.FiveHourThreshold > 0 &&
            fiveHourRemaining <= settings.FiveHourThreshold &&
            !WindowHasReset(usage.ResetAt5h, now))
        {
            yield return new UsageAlertCandidate(
                $"{usage.Provider.ToId()}-5h-low",
                localizer.Text(L10nKey.FiveHourAlertTitle),
                $"{usage.DisplayName} 5h {fiveHourRemaining}% <= {settings.FiveHourThreshold}%");
        }

        if (usage.RemainingPercent7d is { } sevenDayRemaining &&
            settings.SevenDayThreshold > 0 &&
            sevenDayRemaining <= settings.SevenDayThreshold &&
            !WindowHasReset(usage.ResetAt7d, now))
        {
            yield return new UsageAlertCandidate(
                $"{usage.Provider.ToId()}-7d-low",
                localizer.Text(L10nKey.SevenDayAlertTitle),
                $"{usage.DisplayName} 7d {sevenDayRemaining}% <= {settings.SevenDayThreshold}%");
        }

        foreach (var candidate in ResetAlerts(usage, settings, now, localizer))
        {
            yield return candidate;
        }
    }

    /// A balance only ever describes the window it was measured in. Once that
    /// window's reset has passed, the number on hand belongs to a window that has
    /// already refilled, so it is no reason to warn — and a cached reading can sit
    /// on the wrong side of a reset for hours. FormatWindowReset makes the same
    /// call about a cached reading's time; this keeps the alerts in step.
    ///
    /// With no reset instant to judge by there is nothing to go on, so the alert
    /// stands.
    private static bool WindowHasReset(DateTimeOffset? resetAt, DateTimeOffset now)
    {
        if (resetAt is not { } date)
        {
            return false;
        }

        return date <= now;
    }

    /// How long a cached reading may stand before the tray is quietly out of
    /// date: three missed polls, so one failed fetch is not news, with a floor of
    /// 30 minutes — the same freshness bound the status line bridge uses, and
    /// short enough to catch a lapsed token within the hour.
    public static TimeSpan StalledThreshold(int refreshIntervalSeconds) =>
        TimeSpan.FromSeconds(Math.Max(30 * 60, refreshIntervalSeconds * 3));

    /// Collection has stalled: what is on screen is a cached measurement that has
    /// aged past StalledAfter. Nothing else alerts on this, so a lapsed token
    /// went unnoticed for as long as nobody looked — a cached percentage stays
    /// plausible while it quietly stops being current.
    ///
    /// A provider with nothing to show at all is deliberately left alone. It
    /// already reads as "--", which cannot be mistaken for a live number, and
    /// alerting there would fire on the first failed fetch for a provider that
    /// was never signed in to.
    private static UsageAlertCandidate? StalledAlert(
        ProviderUsage usage,
        UsageAlertSettings settings,
        DateTimeOffset now,
        Localizer localizer)
    {
        if (settings.StalledAfter <= TimeSpan.Zero || usage.Source != UsageSource.StaleCache)
        {
            return null;
        }

        var age = now - usage.UpdatedAt;
        if (age <= settings.StalledAfter)
        {
            return null;
        }

        var minutes = Math.Max(0, (int)age.TotalMinutes);
        var ago = minutes < 60 ? $"{minutes}m" : $"{minutes / 60}h{minutes % 60}m";
        // A stable id: one alert per outage, and the tray drops the id once the
        // provider measures again, so the next outage is reported afresh.
        return new UsageAlertCandidate(
            $"{usage.Provider.ToId()}-stalled",
            localizer.Text(L10nKey.StalledAlertTitle),
            localizer.Text(L10nKey.StalledAlertBody)
                .Replace("{provider}", usage.DisplayName, StringComparison.Ordinal)
                .Replace("{time}", ago, StringComparison.Ordinal));
    }

    private static IEnumerable<UsageAlertCandidate> ResetAlerts(
        ProviderUsage usage,
        UsageAlertSettings settings,
        DateTimeOffset now,
        Localizer localizer)
    {
        if (settings.ResetWarningMinutes <= 0)
        {
            yield break;
        }

        var warningWindow = TimeSpan.FromMinutes(settings.ResetWarningMinutes);
        foreach (var reset in new[] { ("5h", usage.ResetAt5h), ("7d", usage.ResetAt7d) })
        {
            if (reset.Item2 is not { } date)
            {
                continue;
            }

            var remaining = date - now;
            if (remaining <= TimeSpan.Zero || remaining > warningWindow)
            {
                continue;
            }

            var minutes = Math.Max(0, (int)Math.Ceiling(remaining.TotalMinutes));
            var resetId = date.ToUnixTimeSeconds();
            yield return new UsageAlertCandidate(
                $"{usage.Provider.ToId()}-{reset.Item1}-reset-{resetId}",
                localizer.Text(L10nKey.ResetAlertTitle),
                localizer.Text(L10nKey.ResetAlertBody)
                    .Replace("{provider}", usage.DisplayName, StringComparison.Ordinal)
                    .Replace("{window}", reset.Item1, StringComparison.Ordinal)
                    .Replace("{time}", $"{minutes}m", StringComparison.Ordinal));
        }
    }
}

public static class UsageSnapshotExtensions
{
    public static ProviderUsage Usage(this UsageSnapshot snapshot, Provider provider) => provider switch
    {
        Provider.Claude => snapshot.Claude,
        Provider.Codex => snapshot.Codex,
        _ => throw new ArgumentOutOfRangeException(nameof(provider), provider, null)
    };

    public static string ToId(this Provider provider) => provider switch
    {
        Provider.Claude => "claude",
        Provider.Codex => "codex",
        _ => provider.ToString().ToLowerInvariant()
    };
}
