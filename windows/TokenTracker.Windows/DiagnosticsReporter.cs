using System.Reflection;
using System.Runtime.InteropServices;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

internal sealed class DiagnosticsReporter
{
    private readonly AppSettings settings;
    private readonly UsageHistoryStore historyStore;
    private readonly UsageSnapshot? snapshot;
    private readonly DateTimeOffset? lastSuccessfulRefreshAt;
    private readonly int runningInstanceCount;

    public DiagnosticsReporter(
        AppSettings settings,
        UsageHistoryStore historyStore,
        UsageSnapshot? snapshot,
        DateTimeOffset? lastSuccessfulRefreshAt,
        int runningInstanceCount)
    {
        this.settings = settings;
        this.historyStore = historyStore;
        this.snapshot = snapshot;
        this.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt;
        this.runningInstanceCount = runningInstanceCount;
    }

    public string DiagnosticsText()
    {
        var lines = new List<string>
        {
            "Token Tracker Diagnostics",
            $"Generated: {IsoString(DateTimeOffset.Now)}",
            $"App version: {AppVersion}",
            $"OS: {RuntimeInformation.OSDescription}",
            $"Architecture: {RuntimeInformation.ProcessArchitecture}",
            $"Display mode: {settings.DisplayMode}",
            $"Provider labels: {settings.ProviderLabelStyle}",
            $"Refresh interval: {settings.RefreshIntervalSeconds}s",
            $"Claude enabled: {settings.ClaudeEnabled}",
            $"Codex enabled: {settings.CodexEnabled}",
            $"Language: {settings.Language}",
            $"Notifications enabled: {settings.NotificationsEnabled}",
            $"5h alert threshold: {settings.FiveHourAlertThreshold}%",
            $"7d alert threshold: {settings.SevenDayAlertThreshold}%",
            $"Reset alert window: {settings.ResetAlertMinutes}m",
            $"History retention: {settings.HistoryRetentionDays}d",
            $"History entries: {historyStore.Load().Count}",
            $"History trend: {HistoryTrendText(AppLanguage.English)}",
            $"Last successful update: {(lastSuccessfulRefreshAt is null ? "none" : IsoString(lastSuccessfulRefreshAt.Value))}",
            $"Running instances: {runningInstanceCount}"
        };

        if (settings.RefreshIntervalSeconds < 60)
        {
            lines.Add($"Refresh warning: {new Localizer(AppLanguage.English).Text(L10nKey.RefreshIntervalWarning)}");
        }

        lines.Add($"Claude credentials file exists: {File.Exists(ClaudeCredentialsPath)}");
        lines.Add($"Codex auth file exists: {File.Exists(CodexAuthPath)}");

        if (snapshot is null)
        {
            lines.Add("Snapshot: none");
        }
        else
        {
            lines.Add($"Snapshot updated: {IsoString(snapshot.UpdatedAt)}");
            lines.AddRange(DiagnosticsLines(snapshot.Claude));
            lines.AddRange(DiagnosticsLines(snapshot.Codex));
        }

        return string.Join(Environment.NewLine, lines);
    }

    public string HistoryTrendText(AppLanguage? language = null)
    {
        if (snapshot is null)
        {
            return new Localizer(language ?? settings.Language).Text(L10nKey.NotEnoughHistory);
        }

        return UsageHistoryFormatter.TrendSummary(
            historyStore.Load(),
            snapshot,
            localizer: new Localizer(language ?? settings.Language));
    }

    public static string ClaudeCredentialsPath => AppPaths.ClaudeCredentialsPath();

    public static string CodexAuthPath => AppPaths.CodexAuthPath();

    private static IEnumerable<string> DiagnosticsLines(ProviderUsage usage)
    {
        var issue = UsageIssueFormatter.Issue(usage, new Localizer(AppLanguage.English));
        return new[]
        {
            $"{usage.DisplayName} source: {usage.Source}",
            $"{usage.DisplayName} status: {issue.Kind}",
            $"{usage.DisplayName} 5h remaining: {DisplayFormatter.FormatPercent(usage.RemainingPercent5h)}",
            $"{usage.DisplayName} 7d remaining: {DisplayFormatter.FormatPercent(usage.RemainingPercent7d)}",
            $"{usage.DisplayName} 5h reset: {IsoStringOrDash(usage.ResetAt5h)}",
            $"{usage.DisplayName} 7d reset: {IsoStringOrDash(usage.ResetAt7d)}",
            $"{usage.DisplayName} plan: {usage.Plan ?? "--"}",
            $"{usage.DisplayName} technical error: {issue.TechnicalDetail ?? "--"}"
        };
    }

    private static string AppVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";

    private static string IsoString(DateTimeOffset date) =>
        date.ToUniversalTime().ToString("O");

    private static string IsoStringOrDash(DateTimeOffset? date) =>
        date is null ? "--" : IsoString(date.Value);
}
