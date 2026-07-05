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
    private readonly Localizer localizer;

    public SettingsForm(
        AppSettings settings,
        Func<Task> onProviderChange,
        Action onGeneralChange,
        Action onNotificationsEnabled)
    {
        this.settings = settings;
        this.onProviderChange = onProviderChange;
        this.onGeneralChange = onGeneralChange;
        this.onNotificationsEnabled = onNotificationsEnabled;
        localizer = new Localizer(settings.Language);

        Text = "Token Tracker";
        Width = 430;
        Height = 470;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;

        BuildContent();
    }

    private void BuildContent()
    {
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            ColumnCount = 2,
            RowCount = 0,
            Padding = new Padding(16)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(layout);

        AddHeader(layout, localizer.Text(L10nKey.Providers));
        AddProviderCheckbox(layout, "Claude", settings.ClaudeEnabled, value => settings.ClaudeEnabled = value);
        AddProviderCheckbox(layout, "Codex", settings.CodexEnabled, value => settings.CodexEnabled = value);

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

    private void AddProviderCheckbox(TableLayoutPanel layout, string label, bool value, Action<bool> setValue) =>
        AddCheckbox(layout, label, value, async enabled =>
        {
            setValue(enabled);
            await onProviderChange();
        });

    private void AddCheckbox(TableLayoutPanel layout, string label, bool value, Action<bool> changed)
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
