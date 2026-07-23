using System.Drawing;
using System.Diagnostics;
using System.Windows.Forms;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

internal sealed class TrayAppContext : ApplicationContext
{
    private const int MaxMenuTextLength = 58;
    private const int MaxMenuWidth = 420;

    private readonly NotifyIcon notifyIcon = new();
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly SettingsStore settingsStore = new();
    private readonly CacheStore cacheStore = new();
    private readonly UsageHistoryStore historyStore = new();
    private readonly UsageClient usageClient = new();
    private readonly ProviderLogoStore providerLogos = new();
    private readonly HashSet<string> deliveredAlertIds = new(StringComparer.Ordinal);
    private AppSettings settings;
    private UsageSnapshot? snapshot;
    private DateTimeOffset? lastSuccessfulRefreshAt;
    private SettingsForm? settingsForm;
    private Icon? currentIcon;
    private bool refreshing;
    private Localizer Localizer => new(settings.Language);

    public TrayAppContext()
    {
        settings = settingsStore.Load();
        settings.LaunchAtLogin = StartupManager.IsEnabled();

        notifyIcon.Visible = true;
        notifyIcon.Text = "Token Tracker";
        notifyIcon.ContextMenuStrip = BuildMenu();
        SetIcon(null);

        timer.Interval = Math.Max(60, settings.RefreshIntervalSeconds) * 1000;
        timer.Tick += async (_, _) => await RefreshAsync();
        timer.Start();

        _ = RefreshAsync();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Dispose();
            notifyIcon.Visible = false;
            notifyIcon.Dispose();
            providerLogos.Dispose();
            currentIcon?.Dispose();
        }

        base.Dispose(disposing);
    }

    private async Task RefreshAsync()
    {
        if (refreshing)
        {
            return;
        }

        if (PauseController.IsPaused(settings.PollPausedUntil))
        {
            // Skip the network fetch while paused; keep the menu's countdown fresh.
            notifyIcon.ContextMenuStrip = BuildMenu();
            return;
        }

        refreshing = true;
        notifyIcon.Text = TrimTooltip("Token Tracker: refreshing...");

        try
        {
            var claudeTask = settings.ClaudeEnabled
                ? usageClient.FetchClaudeAsync()
                : Task.FromResult(ProviderUsage.Unavailable(Provider.Claude, "Disabled"));
            var codexTask = settings.CodexEnabled
                ? usageClient.FetchCodexAsync()
                : Task.FromResult(ProviderUsage.Unavailable(Provider.Codex, "Disabled"));

            await Task.WhenAll(claudeTask, codexTask);
            var freshSnapshot = new UsageSnapshot(claudeTask.Result, codexTask.Result, DateTimeOffset.Now);
            snapshot = UsageSnapshotCachePolicy.Apply(
                freshSnapshot,
                cacheStore.Load(TimeSpan.FromHours(1)),
                settings.ClaudeEnabled,
                settings.CodexEnabled);
            cacheStore.Save(snapshot);
            if (snapshot.Claude.Source == UsageSource.Api || snapshot.Codex.Source == UsageSource.Api)
            {
                lastSuccessfulRefreshAt = snapshot.UpdatedAt;
            }

            historyStore.Append(snapshot, settings.HistoryRetentionDays);
            HandleNotifications(snapshot);
            SetIcon(snapshot);
            notifyIcon.Text = TrimTooltip(DisplayFormatter.Tooltip(snapshot, settings.ProviderLabelStyle));
        }
        catch (Exception ex)
        {
            notifyIcon.Text = TrimTooltip($"Token Tracker: {ex.Message}");
        }
        finally
        {
            refreshing = false;
            notifyIcon.ContextMenuStrip = BuildMenu();
        }
    }

    private void SetIcon(UsageSnapshot? usage)
    {
        var nextIcon = TrayIconRenderer.Render(usage, settings.DisplayMode);
        notifyIcon.Icon = nextIcon;
        currentIcon?.Dispose();
        currentIcon = nextIcon;
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        ConfigureCompactMenu(menu);

        if (snapshot is null)
        {
            AddDisabled(menu.Items, Localizer.Text(L10nKey.NoUsageLoaded));
        }
        else
        {
            AddProvider(menu, snapshot.Claude);
            AddProvider(menu, snapshot.Codex);
            menu.Items.Add(new ToolStripSeparator());
            AddDisabled(menu.Items, $"{Localizer.Text(L10nKey.Updated)} {Relative(snapshot.UpdatedAt)} {Localizer.Text(L10nKey.Ago)}");
            AddDisabled(
                menu.Items,
                lastSuccessfulRefreshAt is null
                    ? Localizer.Text(L10nKey.NoSuccessfulUpdate)
                    : $"{Localizer.Text(L10nKey.LastSuccessfulUpdate)}: {Relative(lastSuccessfulRefreshAt.Value)} {Localizer.Text(L10nKey.Ago)}");
        }

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Localizer.Text(L10nKey.RefreshNow), null, async (_, _) =>
        {
            // A manual refresh is an explicit request to fetch now, so it also
            // lifts an active pause.
            if (PauseController.IsPaused(settings.PollPausedUntil))
            {
                settings.PollPausedUntil = null;
                SaveSettings();
            }

            await RefreshAsync();
        });
        menu.Items.Add(Localizer.Text(L10nKey.Preferences), null, (_, _) => ShowSettings());
        AddPauseControls(menu);
        menu.Items.Add(DiagnosticsMenu());
        menu.Items.Add(HistoryMenu());

        var launchItem = new ToolStripMenuItem(Localizer.Text(L10nKey.LaunchAtLogin))
        {
            Checked = StartupManager.IsEnabled(),
            CheckOnClick = true
        };
        launchItem.Click += (_, _) =>
        {
            StartupManager.SetEnabled(launchItem.Checked);
            settings.LaunchAtLogin = launchItem.Checked;
            SaveSettings();
        };
        menu.Items.Add(launchItem);
        menu.Items.Add(Localizer.Text(L10nKey.AlwaysShowIconSettings), null, (_, _) => OpenTaskbarIconSettings());

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Localizer.Text(L10nKey.Quit), null, (_, _) => ExitThread());

        return menu;
    }

    private void AddProvider(ContextMenuStrip menu, ProviderUsage usage)
    {
        var header = ProviderHeaderText(usage);
        var provider = new ToolStripMenuItem(CompactMenuText(header), ProviderHeaderImage(usage))
        {
            ToolTipText = header
        };
        ConfigureCompactMenu(provider.DropDown);
        if (provider.Image is not null)
        {
            provider.ImageScaling = ToolStripItemImageScaling.None;
        }

        var issue = UsageIssueFormatter.Issue(usage, Localizer);
        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.Status)}: {issue.Title}");
        AddDisabled(provider.DropDownItems, $"  {issue.Detail}");
        if (!string.IsNullOrWhiteSpace(issue.Recovery))
        {
            AddDisabled(provider.DropDownItems, $"  {Localizer.Text(L10nKey.Recovery)}: {issue.Recovery}");
        }

        if (settings.ShowForecast)
        {
            var window = DisplayFormatter.PreferredForecastWindow(usage);
            var resetAt = window == ForecastWindow.FiveHour ? usage.ResetAt5h : usage.ResetAt7d;
            var forecast = UsageForecaster.Forecast(historyStore.Load(), usage.Provider, window, resetAt);
            var forecastLine = UsageForecastText.MenuLine(forecast, window, Localizer);
            if (forecastLine is not null)
            {
                AddDisabled(provider.DropDownItems, $"  {forecastLine}");
            }
        }

        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.FiveHourReset)}: {DisplayFormatter.FormatReset(usage.ResetAt5h)}");
        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.SevenDayReset)}: {DisplayFormatter.FormatReset(usage.ResetAt7d)}");
        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.Source)}: {usage.Source}");

        if (!string.IsNullOrWhiteSpace(issue.TechnicalDetail))
        {
            AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.TechnicalError)}: {issue.TechnicalDetail}");
        }

        if (!string.IsNullOrWhiteSpace(usage.Plan))
        {
            AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.Plan)}: {usage.Plan}");
        }

        menu.Items.Add(provider);
    }

    private string ProviderHeaderText(ProviderUsage usage)
    {
        if (settings.ProviderLabelStyle != ProviderLabelStyle.Icon)
        {
            return DisplayFormatter.DetailLine(usage);
        }

        return $"5h {DisplayFormatter.FormatPercent(usage.RemainingPercent5h)}, 7d {DisplayFormatter.FormatPercent(usage.RemainingPercent7d)}";
    }

    private Image? ProviderHeaderImage(ProviderUsage usage) =>
        settings.ProviderLabelStyle == ProviderLabelStyle.Icon
            ? providerLogos.MenuLogo(usage.Provider)
            : null;

    private void AddPauseControls(ContextMenuStrip menu)
    {
        if (PauseController.IsPaused(settings.PollPausedUntil))
        {
            var remainingText = PauseController.IsIndefinite(settings.PollPausedUntil)
                ? Localizer.Text(L10nKey.PauseUntilResumed)
                : UsageForecaster.DurationText(PauseController.Remaining(settings.PollPausedUntil).TotalSeconds);
            AddDisabled(menu.Items, $"{Localizer.Text(L10nKey.UpdatesPaused)}: {remainingText}");
            menu.Items.Add(Localizer.Text(L10nKey.ResumeNow), null, async (_, _) =>
            {
                settings.PollPausedUntil = null;
                SaveSettings();
                await RefreshAsync();
            });
        }

        var pauseRoot = new ToolStripMenuItem(Localizer.Text(L10nKey.PausePolling));
        pauseRoot.DropDownItems.Add(Localizer.Text(L10nKey.Pause1h), null, (_, _) => PausePolling(TimeSpan.FromHours(1)));
        pauseRoot.DropDownItems.Add(Localizer.Text(L10nKey.Pause3h), null, (_, _) => PausePolling(TimeSpan.FromHours(3)));
        pauseRoot.DropDownItems.Add(Localizer.Text(L10nKey.PauseUntilResumed), null, (_, _) => PausePolling(null));
        menu.Items.Add(pauseRoot);
    }

    private void PausePolling(TimeSpan? duration)
    {
        settings.PollPausedUntil = duration is null
            ? DateTimeOffset.MaxValue
            : DateTimeOffset.Now + duration.Value;
        SaveSettings();
        notifyIcon.ContextMenuStrip = BuildMenu();
    }

    private ToolStripMenuItem DiagnosticsMenu()
    {
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.Diagnostics));
        root.DropDownItems.Add(Localizer.Text(L10nKey.CopyDiagnostics), null, (_, _) =>
        {
            Clipboard.SetText(Diagnostics().DiagnosticsText());
            notifyIcon.ShowBalloonTip(3000, "Token Tracker", Localizer.Text(L10nKey.DiagnosticsCopied), ToolTipIcon.Info);
        });
        root.DropDownItems.Add(new ToolStripSeparator());
        root.DropDownItems.Add(Localizer.Text(L10nKey.OpenClaudeCredentials), null, (_, _) => RevealInExplorer(DiagnosticsReporter.ClaudeCredentialsPath));
        root.DropDownItems.Add(Localizer.Text(L10nKey.OpenCodexAuth), null, (_, _) => RevealInExplorer(DiagnosticsReporter.CodexAuthPath));
        root.DropDownItems.Add(new ToolStripSeparator());
        AddDisabled(root.DropDownItems, $"{Localizer.Text(L10nKey.DuplicateInstances)}: {RunningInstanceCount()}");
        if (settings.RefreshIntervalSeconds < 300)
        {
            AddDisabled(root.DropDownItems, Localizer.Text(L10nKey.RefreshIntervalWarning));
        }

        return root;
    }

    private ToolStripMenuItem HistoryMenu()
    {
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.History));
        AddDisabled(root.DropDownItems, Diagnostics().HistoryTrendText());
        var historyEntries = historyStore.Load();
        foreach (var provider in new[] { Provider.Claude, Provider.Codex })
        {
            var window = snapshot is null
                ? ForecastWindow.FiveHour
                : DisplayFormatter.PreferredForecastWindow(provider == Provider.Claude ? snapshot.Claude : snapshot.Codex);
            var sparkline = SparklineText.Render(SparklineSeries.Build(historyEntries, provider, window));
            if (!string.IsNullOrEmpty(sparkline))
            {
                var name = provider == Provider.Claude ? "Claude" : "Codex";
                AddDisabled(root.DropDownItems, $"{name} {window.ShortLabel()} {sparkline}");
            }
        }

        AddDisabled(root.DropDownItems, $"{Localizer.Text(L10nKey.HistoryRetentionDays)}: {settings.HistoryRetentionDays}d");
        root.DropDownItems.Add(new ToolStripSeparator());
        root.DropDownItems.Add(Localizer.Text(L10nKey.ExportHistoryCsv), null, (_, _) => ExportHistoryCsv());
        return root;
    }

    private DiagnosticsReporter Diagnostics() =>
        new(settings, historyStore, snapshot, lastSuccessfulRefreshAt, RunningInstanceCount());

    private void ShowSettings()
    {
        if (settingsForm is null || settingsForm.IsDisposed)
        {
            settingsForm = new SettingsForm(
                settings,
                async () =>
                {
                    SaveSettings();
                    notifyIcon.ContextMenuStrip = BuildMenu();
                    await RefreshAsync();
                },
                () =>
                {
                    SaveSettings();
                    SetIcon(snapshot);
                    notifyIcon.Text = TrimTooltip(DisplayFormatter.Tooltip(snapshot, settings.ProviderLabelStyle));
                    notifyIcon.ContextMenuStrip = BuildMenu();
                },
                () =>
                {
                    SaveSettings();
                    notifyIcon.ContextMenuStrip = BuildMenu();
                });
            settingsForm.FormClosed += (_, _) => settingsForm = null;
        }

        settingsForm.Show();
        settingsForm.Activate();
    }

    private void ExportHistoryCsv()
    {
        using var dialog = new SaveFileDialog
        {
            FileName = "token-tracker-history.csv",
            Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
            DefaultExt = "csv",
            AddExtension = true
        };

        if (dialog.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        try
        {
            File.WriteAllText(dialog.FileName, historyStore.CsvString());
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Token Tracker", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void HandleNotifications(UsageSnapshot usage)
    {
        if (!settings.NotificationsEnabled)
        {
            deliveredAlertIds.Clear();
            return;
        }

        var candidates = UsageAlertEvaluator.Candidates(
            usage,
            new UsageAlertSettings(
                settings.NotificationsEnabled,
                settings.FiveHourAlertThreshold,
                settings.SevenDayAlertThreshold,
                settings.ResetAlertMinutes),
            localizer: Localizer).ToList();
        candidates.AddRange(ForecastCandidates(usage));
        var activeIds = candidates.Select(candidate => candidate.Id).ToHashSet(StringComparer.Ordinal);
        deliveredAlertIds.IntersectWith(activeIds);

        foreach (var candidate in candidates.Where(candidate => deliveredAlertIds.Add(candidate.Id)))
        {
            notifyIcon.ShowBalloonTip(5000, candidate.Title, candidate.Body, ToolTipIcon.Warning);
        }
    }

    private IReadOnlyList<UsageAlertCandidate> ForecastCandidates(UsageSnapshot usage)
    {
        if (!settings.DepletionAlertEnabled)
        {
            return Array.Empty<UsageAlertCandidate>();
        }

        var entries = historyStore.Load();
        var inputs = new List<ForecastAlertInput>();
        foreach (var provider in new[] { Provider.Claude, Provider.Codex })
        {
            var providerUsage = usage.Usage(provider);
            var fiveHour = UsageForecaster.Forecast(entries, provider, ForecastWindow.FiveHour, providerUsage.ResetAt5h, usage.UpdatedAt);
            if (fiveHour is not null)
            {
                inputs.Add(new ForecastAlertInput(provider, ForecastWindow.FiveHour, fiveHour, providerUsage.ResetAt5h));
            }

            var sevenDay = UsageForecaster.Forecast(entries, provider, ForecastWindow.SevenDay, providerUsage.ResetAt7d, usage.UpdatedAt);
            if (sevenDay is not null)
            {
                inputs.Add(new ForecastAlertInput(provider, ForecastWindow.SevenDay, sevenDay, providerUsage.ResetAt7d));
            }
        }

        return UsageForecastAlert.Candidates(inputs, enabled: true, Localizer);
    }

    private static void AddDisabled(ToolStripItemCollection items, string text, Image? image = null) =>
        items.Add(DisabledItem(text, image));

    private static void ConfigureCompactMenu(ToolStrip menu)
    {
        menu.ImageScalingSize = new Size(16, 16);
        menu.MaximumSize = new Size(MaxMenuWidth, 0);
        menu.ShowItemToolTips = true;
    }

    private static ToolStripMenuItem DisabledItem(string text, Image? image = null)
    {
        var displayText = CompactMenuText(text);
        var item = new ToolStripMenuItem(displayText, image)
        {
            Enabled = false
        };

        if (image is not null)
        {
            item.ImageScaling = ToolStripItemImageScaling.None;
        }

        if (!string.Equals(displayText, text, StringComparison.Ordinal))
        {
            item.AutoToolTip = false;
            item.ToolTipText = text;
        }

        return item;
    }

    private static string CompactMenuText(string text)
    {
        var singleLine = text
            .Replace("\r\n", " ")
            .Replace('\n', ' ')
            .Replace('\r', ' ');

        if (singleLine.Length <= MaxMenuTextLength)
        {
            return singleLine;
        }

        return singleLine[..(MaxMenuTextLength - 3)].TrimEnd() + "...";
    }

    private void SaveSettings()
    {
        timer.Interval = Math.Max(60, settings.RefreshIntervalSeconds) * 1000;
        settingsStore.Save(settings);
    }

    private void OpenTaskbarIconSettings()
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:taskbar")
            {
                UseShellExecute = true
            });

            notifyIcon.ShowBalloonTip(
                5000,
                "Token Tracker",
                Localizer.Text(L10nKey.TaskbarSettingsTip),
                ToolTipIcon.Info);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"{Localizer.Text(L10nKey.TaskbarSettingsFallback)}\n\n{ex.Message}",
                "Token Tracker",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }

    private static void RevealInExplorer(string path)
    {
        var existingPath = File.Exists(path) ? path : Path.GetDirectoryName(path);
        if (string.IsNullOrWhiteSpace(existingPath))
        {
            return;
        }

        var arguments = File.Exists(path)
            ? $"/select,\"{path}\""
            : $"\"{existingPath}\"";
        Process.Start(new ProcessStartInfo("explorer.exe", arguments)
        {
            UseShellExecute = true
        });
    }

    private static int RunningInstanceCount()
    {
        using var current = Process.GetCurrentProcess();
        var processes = Process.GetProcessesByName(current.ProcessName);
        try
        {
            return processes.Length;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static string Relative(DateTimeOffset date)
    {
        var elapsed = DateTimeOffset.Now - date;
        if (elapsed.TotalMinutes < 1)
        {
            return $"{Math.Max(0, (int)elapsed.TotalSeconds)}s";
        }

        if (elapsed.TotalHours < 1)
        {
            return $"{(int)elapsed.TotalMinutes}m";
        }

        return $"{(int)elapsed.TotalHours}h";
    }

    private static string TrimTooltip(string text) =>
        text.Length <= 63 ? text : text[..60] + "...";
}
