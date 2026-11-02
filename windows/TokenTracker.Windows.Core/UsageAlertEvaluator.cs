using System.Globalization;

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

    /// A window that had run low has reset and can be used again. The low-balance
    /// alert said to hold off; this says when that is over, which otherwise only
    /// shows to someone who opens the menu.
    ///
    /// <paramref name="previous"/> holds each provider's last reading with numbers,
    /// whatever its source, so a reset that passes during an outage is still
    /// reported once the provider is measured again. Only a measurement can say the
    /// window refilled. The alert fires on the one poll that sees the change: by the
    /// next, the refilled reading has become <paramref name="previous"/> and the
    /// condition no longer holds.
    public static IReadOnlyList<UsageAlertCandidate> FreedUpCandidates(
        IReadOnlyDictionary<Provider, ProviderUsage> previous,
        UsageSnapshot current,
        UsageAlertSettings settings,
        Localizer? localizer = null)
    {
        if (!settings.NotificationsEnabled)
        {
            return Array.Empty<UsageAlertCandidate>();
        }

        localizer ??= new Localizer(AppLanguage.English);
        var candidates = new List<UsageAlertCandidate>();
        foreach (var provider in new[] { Provider.Claude, Provider.Codex })
        {
            var after = current.Usage(provider);
            if (!previous.TryGetValue(provider, out var before) ||
                (after.Source != UsageSource.Api && after.Source != UsageSource.StatusLine))
            {
                continue;
            }

            var windows = new[]
            {
                ("5h", settings.FiveHourThreshold, before.RemainingPercent5h, before.ResetAt5h, after.RemainingPercent5h),
                ("7d", settings.SevenDayThreshold, before.RemainingPercent7d, before.ResetAt7d, after.RemainingPercent7d)
            };
            foreach (var (label, threshold, was, resetAt, now) in windows)
            {
                if (threshold <= 0 ||
                    was is not { } wasPercent || wasPercent > threshold ||
                    resetAt is not { } resetDate || resetDate > after.UpdatedAt ||
                    now is not { } nowPercent || nowPercent <= threshold || nowPercent <= wasPercent)
                {
                    continue;
                }

                candidates.Add(new UsageAlertCandidate(
                    $"{provider.ToId()}-{label}-freed-{resetDate.ToUnixTimeSeconds()}",
                    localizer.Text(L10nKey.FreedUpAlertTitle),
                    localizer.Text(L10nKey.FreedUpAlertBody)
                        .Replace("{provider}", after.DisplayName, StringComparison.Ordinal)
                        .Replace("{window}", label, StringComparison.Ordinal)
                        .Replace("{percent}", nowPercent.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal)));
            }
        }

        return candidates;
    }

    /// What <see cref="FreedUpCandidates"/> compares against on the next poll. A
    /// measurement replaces the provider's entry; a cached or missing reading leaves
    /// it alone, so an outage does not erase the low balance a reset will be
    /// measured against. A cached reading still fills an empty entry, which is how
    /// a cached snapshot seeds the map at launch.
    public static Dictionary<Provider, ProviderUsage> LastReadings(
        IReadOnlyDictionary<Provider, ProviderUsage> previous,
        UsageSnapshot snapshot)
    {
        var readings = new Dictionary<Provider, ProviderUsage>(previous);
        foreach (var provider in new[] { Provider.Claude, Provider.Codex })
        {
            var usage = snapshot.Usage(provider);
            if (!usage.IsAvailable)
            {
                continue;
            }

            if (usage.Source == UsageSource.Api || usage.Source == UsageSource.StatusLine || !readings.ContainsKey(provider))
            {
                readings[provider] = usage;
            }
        }

        return readings;
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
