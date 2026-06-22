using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

public sealed class AppSettings
{
    public DisplayMode DisplayMode { get; set; } = DisplayMode.LowestRemaining;
    public ProviderLabelStyle ProviderLabelStyle { get; set; } = ProviderLabelStyle.Abbreviation;
    public int RefreshIntervalSeconds { get; set; } = 60;
    public bool ClaudeEnabled { get; set; } = true;
    public bool CodexEnabled { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public AppLanguage Language { get; set; } = AppLanguage.System;
    public bool NotificationsEnabled { get; set; }
    public int FiveHourAlertThreshold { get; set; } = 20;
    public int SevenDayAlertThreshold { get; set; } = 10;
    public int ResetAlertMinutes { get; set; } = 10;
    public int HistoryRetentionDays { get; set; } = 7;
}

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string Path { get; }

    public SettingsStore(string? path = null)
    {
        Path = path ?? AppPaths.SettingsPath;
    }

    public AppSettings Load()
    {
        if (!File.Exists(Path))
        {
            return new AppSettings();
        }

        try
        {
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(Path), Options) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        File.WriteAllText(Path, JsonSerializer.Serialize(settings, Options));
    }
}
