using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

public sealed class AppSettings
{
    public DisplayMode DisplayMode { get; set; } = DisplayMode.LowestRemaining;
    public ProviderLabelStyle ProviderLabelStyle { get; set; } = ProviderLabelStyle.Abbreviation;
    public int RefreshIntervalSeconds { get; set; } = 300;
    public bool ClaudeEnabled { get; set; } = true;
    public bool CodexEnabled { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public AppLanguage Language { get; set; } = AppLanguage.System;
    public bool NotificationsEnabled { get; set; }
    public int FiveHourAlertThreshold { get; set; } = 20;
    public int SevenDayAlertThreshold { get; set; } = 10;
    public int ResetAlertMinutes { get; set; } = 10;
    public int HistoryRetentionDays { get; set; } = 7;
    public bool ShowForecast { get; set; } = true;
    public bool DepletionAlertEnabled { get; set; }

    /// When updates are paused, the instant polling resumes (persisted, so a
    /// restart during a pause stays paused). <c>null</c> means not paused.
    public DateTimeOffset? PollPausedUntil { get; set; }
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
            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(Path), Options) ?? new AppSettings();
            // A saved interval below the current 60s floor (for example the removed
            // 30s option) is no longer selectable and must never poll faster than
            // the floor, so raise it on load. Values at or above 60s are untouched.
            if (settings.RefreshIntervalSeconds < 60)
            {
                settings.RefreshIntervalSeconds = 60;
            }

            return settings;
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        // Atomic write (temp + move) so a crash mid-save can't truncate the
        // settings file — matches UsageHistoryStore.Save.
        var tempPath = Path + ".tmp";
        File.WriteAllText(tempPath, JsonSerializer.Serialize(settings, Options));
        File.Move(tempPath, Path, overwrite: true);
    }
}
