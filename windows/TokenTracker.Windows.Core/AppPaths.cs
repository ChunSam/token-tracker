namespace TokenTracker.Windows.Core;

public static class AppPaths
{
    public static string HomeDirectory =>
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public static string AppDataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Token Tracker");

    public static string SettingsPath =>
        Path.Combine(AppDataDirectory, "settings.json");

    public static string SnapshotCachePath =>
        Path.Combine(AppDataDirectory, "usage-cache.json");

    public static string UsageHistoryPath =>
        Path.Combine(AppDataDirectory, "usage-history.json");

    public static string CodexAuthPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".codex", "auth.json");

    public static string ClaudeCredentialsPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".claude", ".credentials.json");
}
