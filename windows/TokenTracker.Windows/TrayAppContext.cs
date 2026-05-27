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
    private readonly UsageClient usageClient = new();
    private readonly ProviderLogoStore providerLogos = new();
    private AppSettings settings;
    private UsageSnapshot? snapshot;
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
        }

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Localizer.Text(L10nKey.RefreshNow), null, async (_, _) => await RefreshAsync());
        menu.Items.Add(DisplayModeMenu());
        menu.Items.Add(ProviderLabelStyleMenu());
        menu.Items.Add(ProvidersMenu());
        menu.Items.Add(RefreshIntervalMenu());
        menu.Items.Add(LanguageMenu());

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

        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.FiveHourReset)}: {DisplayFormatter.FormatReset(usage.ResetAt5h)}");
        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.SevenDayReset)}: {DisplayFormatter.FormatReset(usage.ResetAt7d)}");
        AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.Source)}: {usage.Source}");

        if (!string.IsNullOrWhiteSpace(usage.Error))
        {
            AddDisabled(provider.DropDownItems, $"{Localizer.Text(L10nKey.Error)}: {usage.Error}");
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

    private ToolStripMenuItem DisplayModeMenu()
    {
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.DisplayMode));
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
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.Providers));
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
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.RefreshInterval));
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
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.ProviderLabels));
        foreach (var style in Enum.GetValues<ProviderLabelStyle>())
        {
            var item = new ToolStripMenuItem(ProviderLabelStyleLabel(style))
            {
                Checked = settings.ProviderLabelStyle == style,
                Image = style == ProviderLabelStyle.Icon ? providerLogos.MenuLogo(Provider.Codex) : null
            };
            if (item.Image is not null)
            {
                item.ImageScaling = ToolStripItemImageScaling.None;
            }
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

    private string ProviderLabelStyleLabel(ProviderLabelStyle style) => style switch
    {
        ProviderLabelStyle.Abbreviation => "Cdx / Cl",
        ProviderLabelStyle.Icon => Localizer.Text(L10nKey.OfficialLogos),
        _ => style.ToString()
    };

    private ToolStripMenuItem LanguageMenu()
    {
        var root = new ToolStripMenuItem(Localizer.Text(L10nKey.Language));
        foreach (var language in Enum.GetValues<AppLanguage>())
        {
            var item = new ToolStripMenuItem(Localizer.LanguageLabel(language))
            {
                Checked = settings.Language == language
            };
            item.Click += (_, _) =>
            {
                settings.Language = language;
                SaveSettings();
                notifyIcon.ContextMenuStrip = BuildMenu();
            };
            root.DropDownItems.Add(item);
        }

        return root;
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
        timer.Interval = Math.Max(15, settings.RefreshIntervalSeconds) * 1000;
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

    private string DisplayModeLabel(DisplayMode mode) => mode switch
    {
        DisplayMode.LowestRemaining => Localizer.Text(L10nKey.LowestRemaining),
        DisplayMode.Both => Localizer.Text(L10nKey.Both),
        DisplayMode.CodexOnly => Localizer.Text(L10nKey.CodexOnly),
        DisplayMode.ClaudeOnly => Localizer.Text(L10nKey.ClaudeOnly),
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
