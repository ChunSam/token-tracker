namespace TokenTracker.Windows.Core;

public sealed record UsageAlertSettings
{
    public UsageAlertSettings(
        bool notificationsEnabled,
        int fiveHourThreshold,
        int sevenDayThreshold,
        int resetWarningMinutes)
    {
        NotificationsEnabled = notificationsEnabled;
        FiveHourThreshold = Math.Clamp(fiveHourThreshold, 0, 100);
        SevenDayThreshold = Math.Clamp(sevenDayThreshold, 0, 100);
        ResetWarningMinutes = Math.Max(0, resetWarningMinutes);
    }

    public bool NotificationsEnabled { get; }
    public int FiveHourThreshold { get; }
    public int SevenDayThreshold { get; }
    public int ResetWarningMinutes { get; }
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

        if (usage.RemainingPercent5h is { } fiveHourRemaining &&
            settings.FiveHourThreshold > 0 &&
            fiveHourRemaining <= settings.FiveHourThreshold)
        {
            yield return new UsageAlertCandidate(
                $"{usage.Provider.ToId()}-5h-low",
                localizer.Text(L10nKey.FiveHourAlertTitle),
                $"{usage.DisplayName} 5h {fiveHourRemaining}% <= {settings.FiveHourThreshold}%");
        }

        if (usage.RemainingPercent7d is { } sevenDayRemaining &&
            settings.SevenDayThreshold > 0 &&
            sevenDayRemaining <= settings.SevenDayThreshold)
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
                $"{usage.DisplayName} {reset.Item1} reset in {minutes}m");
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
