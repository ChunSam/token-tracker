using System.Drawing;
using System.Windows.Forms;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

internal sealed class SettingsForm : Form
{
    private readonly AppSettings settings;
    private readonly Func<Task> onProviderChange;
    private readonly Action onGeneralChange;
    private readonly Action onNotificationsEnabled;
    private readonly Func<Task> onCostChange;
    private readonly IAdminKeyStore adminKeys = new DpapiAdminKeyStore();
    private Localizer localizer;

    public SettingsForm(
        AppSettings settings,
        Func<Task> onProviderChange,
        Action onGeneralChange,
        Action onNotificationsEnabled,
        Func<Task> onCostChange)
    {
        this.settings = settings;
        this.onProviderChange = onProviderChange;
        this.onGeneralChange = onGeneralChange;
        this.onNotificationsEnabled = onNotificationsEnabled;
        this.onCostChange = onCostChange;
        localizer = new Localizer(settings.Language);

        Text = "Tokki";
        Width = 470;
        Height = 600;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;

        BuildContent();
    }

    private void RebuildContent()
    {
        localizer = new Localizer(settings.Language);
        var previous = Controls.Cast<Control>().ToArray();
        Controls.Clear();
        foreach (var control in previous)
        {
            control.Dispose();
        }

        BuildContent();
    }

    private void BuildContent()
    {
        // The panel scrolls and the table grows to its content. A TableLayoutPanel
        // that scrolls itself undercounts its height, so its last row and bottom
        // padding sat out of reach at the end of the scroll.
        var scroller = new Panel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true
        };
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 2,
            RowCount = 0,
            Padding = new Padding(16)
        };
        // Labels take what the longest needs and checkboxes the rest; a fixed label
        // column left the longer checkbox texts clipped.
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        scroller.Controls.Add(layout);
        Controls.Add(scroller);

        AddHeader(layout, "Claude");
        AddProviderCheckbox(layout, localizer.Text(L10nKey.SubscriptionLimits), settings.ClaudeEnabled, value => settings.ClaudeEnabled = value);
        AddCheckbox(layout, localizer.Text(L10nKey.RenewClaudeTokenWithCli), settings.RenewClaudeTokenWithCli, value =>
        {
            settings.RenewClaudeTokenWithCli = value;
            onGeneralChange();
        });
        AddApiCostRows(
            layout,
            Provider.Claude,
            settings.ClaudeCostEnabled,
            value => settings.ClaudeCostEnabled = value,
            settings.ClaudeMonthlyBudget,
            value => settings.ClaudeMonthlyBudget = value);

        AddHeader(layout, "Codex");
        AddProviderCheckbox(layout, localizer.Text(L10nKey.SubscriptionLimits), settings.CodexEnabled, value => settings.CodexEnabled = value);
        AddApiCostRows(
            layout,
            Provider.Codex,
            settings.CodexCostEnabled,
            value => settings.CodexCostEnabled = value,
            settings.CodexMonthlyBudget,
            value => settings.CodexMonthlyBudget = value);

        AddHeader(layout, localizer.Text(L10nKey.General));

        AddCombo(
            layout,
            localizer.Text(L10nKey.DisplayMode),
            Enum.GetValues<DisplayMode>().Select(mode => new Option<DisplayMode>(DisplayModeLabel(mode), mode)),
            settings.DisplayMode,
            value =>
            {
                settings.DisplayMode = value;
                onGeneralChange();
            });
        AddCombo(
            layout,
            localizer.Text(L10nKey.ProviderLabels),
            Enum.GetValues<ProviderLabelStyle>().Select(style => new Option<ProviderLabelStyle>(ProviderLabelStyleLabel(style), style)),
            settings.ProviderLabelStyle,
            value =>
            {
                settings.ProviderLabelStyle = value;
                onGeneralChange();
            });
        AddCombo(
            layout,
            localizer.Text(L10nKey.RefreshInterval),
            new[]
            {
                new Option<int>("1m", 60),
                new Option<int>("5m", 300),
                new Option<int>("15m", 900)
            },
            settings.RefreshIntervalSeconds,
            value =>
            {
                settings.RefreshIntervalSeconds = value;
                onGeneralChange();
            });
        AddCombo(
            layout,
            localizer.Text(L10nKey.Language),
            Enum.GetValues<AppLanguage>().Select(language => new Option<AppLanguage>(Localizer.LanguageLabel(language), language)),
            settings.Language,
            value =>
            {
                settings.Language = value;
                onGeneralChange();
                // Re-localize this form's own labels. Deferred via BeginInvoke so
                // we don't dispose the combo from inside its own change event.
                BeginInvoke(new Action(RebuildContent));
            });
        AddCheckbox(layout, localizer.Text(L10nKey.ShowForecastLabel), settings.ShowForecast, value =>
        {
            settings.ShowForecast = value;
            onGeneralChange();
        });
        AddCheckbox(layout, localizer.Text(L10nKey.ShowResetCountdownLabel), settings.ShowResetCountdown, value =>
        {
            settings.ShowResetCountdown = value;
            onGeneralChange();
        });
        AddCheckbox(layout, localizer.Text(L10nKey.CheckForUpdates), settings.CheckForUpdates, value =>
        {
            settings.CheckForUpdates = value;
            onGeneralChange();
        });

        AddHeader(layout, localizer.Text(L10nKey.Notifications));
        AddCheckbox(
            layout,
            localizer.Text(L10nKey.StatusEnabled),
            settings.NotificationsEnabled,
            value =>
            {
                settings.NotificationsEnabled = value;
                if (value)
                {
                    onNotificationsEnabled();
                }
                else
                {
                    onGeneralChange();
                }
            });
        AddNumber(layout, localizer.Text(L10nKey.FiveHourAlertThreshold), settings.FiveHourAlertThreshold, 0, 100, "%", value =>
        {
            settings.FiveHourAlertThreshold = value;
            onGeneralChange();
        });
        AddNumber(layout, localizer.Text(L10nKey.SevenDayAlertThreshold), settings.SevenDayAlertThreshold, 0, 100, "%", value =>
        {
            settings.SevenDayAlertThreshold = value;
            onGeneralChange();
        });
        AddNumber(layout, localizer.Text(L10nKey.ResetAlertMinutes), settings.ResetAlertMinutes, 0, 1440, "m", value =>
        {
            settings.ResetAlertMinutes = value;
            onGeneralChange();
        });
        AddCheckbox(layout, localizer.Text(L10nKey.DepletionAlertToggle), settings.DepletionAlertEnabled, value =>
        {
            settings.DepletionAlertEnabled = value;
            onGeneralChange();
        });

        AddNumber(layout, localizer.Text(L10nKey.StaleToleranceHours), settings.StaleToleranceHours, 1, 48, "h", value =>
        {
            settings.StaleToleranceHours = value;
            onGeneralChange();
        });

        AddHeader(layout, localizer.Text(L10nKey.History));
        AddNumber(layout, localizer.Text(L10nKey.HistoryRetentionDays), settings.HistoryRetentionDays, 1, 365, "d", value =>
        {
            settings.HistoryRetentionDays = value;
            onGeneralChange();
        });
    }

    private void AddHeader(TableLayoutPanel layout, string title)
    {
        var label = new Label
        {
            Text = title,
            Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold),
            AutoSize = true,
            Margin = new Padding(0, 12, 0, 4)
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(label, 0, layout.RowCount);
        layout.SetColumnSpan(label, 2);
        layout.RowCount++;
    }

    /// The organization's API cost: on or off, its monthly budget, its Admin key.
    private void AddApiCostRows(
        TableLayoutPanel layout,
        Provider provider,
        bool enabled,
        Action<bool> setEnabled,
        int budget,
        Action<int> setBudget)
    {
        var toggle = AddCheckbox(layout, localizer.Text(L10nKey.ApiCost), enabled, async value =>
        {
            setEnabled(value);
            await onCostChange();
        });
        AddNumber(layout, localizer.Text(L10nKey.MonthlyBudget), budget, 0, 1_000_000, "USD", value =>
        {
            setBudget(value);
            onGeneralChange();
        });

        var button = new Button
        {
            Text = localizer.Text(L10nKey.AdminKeyButton),
            AutoSize = true,
            Margin = new Padding(0, 4, 0, 4)
        };
        button.Click += async (_, _) =>
        {
            var change = AdminKeyDialog.Run(this, provider, adminKeys, localizer);
            if (change == AdminKeyChange.Saved && !toggle.Checked)
            {
                // Storing a key is asking for its cost. With the box left unticked
                // it did nothing at all, and that second step was easy to miss.
                // Ticking it saves the setting and fetches, through CheckedChanged.
                toggle.Checked = true;
            }
            else if (change != AdminKeyChange.None)
            {
                await onCostChange();
            }
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(button, 1, layout.RowCount);
        layout.RowCount++;
    }

    private void AddProviderCheckbox(TableLayoutPanel layout, string label, bool value, Action<bool> setValue) =>
        AddCheckbox(layout, label, value, async enabled =>
        {
            setValue(enabled);
            await onProviderChange();
        });

    private CheckBox AddCheckbox(TableLayoutPanel layout, string label, bool value, Action<bool> changed)
    {
        var checkbox = new CheckBox
        {
            Text = label,
            Checked = value,
            AutoSize = true,
            Margin = new Padding(0, 4, 0, 4)
        };
        checkbox.CheckedChanged += (_, _) => changed(checkbox.Checked);

        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(checkbox, 1, layout.RowCount);
        layout.RowCount++;
        return checkbox;
    }

    private void AddCombo<T>(
        TableLayoutPanel layout,
        string label,
        IEnumerable<Option<T>> options,
        T selected,
        Action<T> changed)
        where T : notnull
    {
        var labelView = RowLabel(label);
        var combo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 190,
            Margin = new Padding(0, 4, 0, 4)
        };
        var optionList = options.ToList();
        combo.Items.AddRange(optionList.Cast<object>().ToArray());
        var selectedIndex = optionList.FindIndex(option => EqualityComparer<T>.Default.Equals(option.Value, selected));
        combo.SelectedIndex = selectedIndex >= 0 ? selectedIndex : 0;
        combo.SelectedIndexChanged += (_, _) =>
        {
            if (combo.SelectedItem is Option<T> option)
            {
                changed(option.Value);
            }
        };

        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(labelView, 0, layout.RowCount);
        layout.Controls.Add(combo, 1, layout.RowCount);
        layout.RowCount++;
    }

    private void AddNumber(
        TableLayoutPanel layout,
        string label,
        int value,
        int min,
        int max,
        string suffix,
        Action<int> changed)
    {
        var labelView = RowLabel(label);
        var panel = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(0, 4, 0, 4)
        };
        var number = new NumericUpDown
        {
            Minimum = min,
            Maximum = max,
            Value = Math.Clamp(value, min, max),
            Width = 80
        };
        var suffixLabel = new Label
        {
            Text = suffix,
            AutoSize = true,
            Padding = new Padding(4, 4, 0, 0)
        };
        number.ValueChanged += (_, _) => changed((int)number.Value);
        panel.Controls.Add(number);
        panel.Controls.Add(suffixLabel);

        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(labelView, 0, layout.RowCount);
        layout.Controls.Add(panel, 1, layout.RowCount);
        layout.RowCount++;
    }

    private Label RowLabel(string text) => new()
    {
        Text = text,
        AutoSize = true,
        Margin = new Padding(0, 8, 12, 4)
    };

    private string DisplayModeLabel(DisplayMode mode) => mode switch
    {
        DisplayMode.LowestRemaining => localizer.Text(L10nKey.LowestRemaining),
        DisplayMode.Both => localizer.Text(L10nKey.Both),
        DisplayMode.CodexOnly => localizer.Text(L10nKey.CodexOnly),
        DisplayMode.ClaudeOnly => localizer.Text(L10nKey.ClaudeOnly),
        _ => mode.ToString()
    };

    private string ProviderLabelStyleLabel(ProviderLabelStyle style) => style switch
    {
        ProviderLabelStyle.Abbreviation => "Cdx / Cl",
        ProviderLabelStyle.Icon => localizer.Text(L10nKey.OfficialLogos),
        _ => style.ToString()
    };

    private sealed record Option<T>(string Label, T Value)
    {
        public override string ToString() => Label;
    }
}
