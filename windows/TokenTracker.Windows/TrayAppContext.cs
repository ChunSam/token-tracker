using System.Drawing;
using System.Windows.Forms;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

internal sealed class TrayAppContext : ApplicationContext
{
    private readonly NotifyIcon notifyIcon = new();
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly SettingsStore settingsStore = new();
    private readonly UsageClient usageClient = new();
    private AppSettings settings;
    private UsageSnapshot? snapshot;
    private Icon? currentIcon;
    private bool refreshing;

    public TrayAppContext()
    {
        settings = settingsStore.Load();
        settings.LaunchAtLogin = StartupManager.IsEnabled();

        notifyIcon.Visible = true;
        notifyIcon.Text = "Token Tracker";
        notifyIcon.ContextMenuStrip = BuildMenu();
        SetIcon(null);

        timer.Interval = Math.Max(15, settings.RefreshIntervalSeconds) * 1000;
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
            snapshot = new UsageSnapshot(claudeTask.Result, codexTask.Result, DateTimeOffset.Now);
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

        if (snapshot is null)
        {
            AddDisabled(menu, "No usage loaded yet");
        }
        else
        {
            AddProvider(menu, snapshot.Claude);
            menu.Items.Add(new ToolStripSeparator());
            AddProvider(menu, snapshot.Codex);
            menu.Items.Add(new ToolStripSeparator());
            AddDisabled(menu, $"Updated {Relative(snapshot.UpdatedAt)} ago");
        }

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Refresh Now", null, async (_, _) => await RefreshAsync());
        menu.Items.Add(DisplayModeMenu());
        menu.Items.Add(ProviderLabelStyleMenu());
        menu.Items.Add(ProvidersMenu());
        menu.Items.Add(RefreshIntervalMenu());

        var launchItem = new ToolStripMenuItem("Launch at Login")
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

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());

        return menu;
    }

    private void AddProvider(ContextMenuStrip menu, ProviderUsage usage)
    {
        AddDisabled(menu, DisplayFormatter.DetailLine(usage));
        AddDisabled(menu, $"  5h reset: {DisplayFormatter.FormatReset(usage.ResetAt5h)}");
        AddDisabled(menu, $"  7d reset: {DisplayFormatter.FormatReset(usage.ResetAt7d)}");
        AddDisabled(menu, $"  Source: {usage.Source}");

        if (!string.IsNullOrWhiteSpace(usage.Error))
        {
            AddDisabled(menu, $"  Error: {usage.Error}");
        }

        if (!string.IsNullOrWhiteSpace(usage.Plan))
        {
            AddDisabled(menu, $"  Plan: {usage.Plan}");
        }
    }

    private ToolStripMenuItem DisplayModeMenu()
    {
        var root = new ToolStripMenuItem("Display Mode");
        foreach (var mode in Enum.GetValues<DisplayMode>())
        {
            var item = new ToolStripMenuItem(DisplayModeLabel(mode))
            {
                Checked = settings.DisplayMode == mode
            };
            item.Click += (_, _) =>
            {
                settings.DisplayMode = mode;
                SaveSettings();
                SetIcon(snapshot);
                notifyIcon.ContextMenuStrip = BuildMenu();
            };
            root.DropDownItems.Add(item);
        }

        return root;
    }

    private ToolStripMenuItem ProvidersMenu()
    {
        var root = new ToolStripMenuItem("Providers");
        root.DropDownItems.Add(ProviderToggleItem("Claude", settings.ClaudeEnabled, enabled => settings.ClaudeEnabled = enabled));
        root.DropDownItems.Add(ProviderToggleItem("Codex", settings.CodexEnabled, enabled => settings.CodexEnabled = enabled));
        return root;
    }

    private ToolStripMenuItem ProviderToggleItem(string label, bool enabled, Action<bool> setEnabled)
    {
        var item = new ToolStripMenuItem(label)
        {
            Checked = enabled,
            CheckOnClick = true
        };
        item.Click += async (_, _) =>
        {
            setEnabled(item.Checked);
            SaveSettings();
            notifyIcon.ContextMenuStrip = BuildMenu();
            await RefreshAsync();
        };
        return item;
    }

    private ToolStripMenuItem RefreshIntervalMenu()
    {
        var root = new ToolStripMenuItem("Refresh Interval");
        foreach (var option in new[] { 30, 60, 300 })
        {
            var item = new ToolStripMenuItem(option < 60 ? $"{option}s" : $"{option / 60}m")
            {
                Checked = settings.RefreshIntervalSeconds == option
            };
            item.Click += (_, _) =>
            {
                settings.RefreshIntervalSeconds = option;
                SaveSettings();
                notifyIcon.ContextMenuStrip = BuildMenu();
            };
            root.DropDownItems.Add(item);
        }

        return root;
    }

    private ToolStripMenuItem ProviderLabelStyleMenu()
    {
        var root = new ToolStripMenuItem("Provider Labels");
        foreach (var style in Enum.GetValues<ProviderLabelStyle>())
        {
            var item = new ToolStripMenuItem(style == ProviderLabelStyle.Abbreviation ? "Cdx / Cl" : "Names")
            {
                Checked = settings.ProviderLabelStyle == style
            };
            item.Click += (_, _) =>
            {
                settings.ProviderLabelStyle = style;
                SaveSettings();
                notifyIcon.Text = TrimTooltip(DisplayFormatter.Tooltip(snapshot, settings.ProviderLabelStyle));
                notifyIcon.ContextMenuStrip = BuildMenu();
            };
            root.DropDownItems.Add(item);
        }

        return root;
    }

    private static void AddDisabled(ContextMenuStrip menu, string text) =>
        menu.Items.Add(new ToolStripMenuItem(text) { Enabled = false });

    private void SaveSettings()
    {
        timer.Interval = Math.Max(15, settings.RefreshIntervalSeconds) * 1000;
        settingsStore.Save(settings);
    }

    private static string DisplayModeLabel(DisplayMode mode) => mode switch
    {
        DisplayMode.LowestRemaining => "Lowest remaining",
        DisplayMode.Both => "Claude + Codex",
        DisplayMode.CodexOnly => "Codex only",
        DisplayMode.ClaudeOnly => "Claude only",
        _ => mode.ToString()
    };

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
