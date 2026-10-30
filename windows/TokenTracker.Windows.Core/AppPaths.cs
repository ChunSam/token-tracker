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

    public static string ClaudeRateLimitStatePath =>
        Path.Combine(AppDataDirectory, "claude-rate-limit.json");

    // Per provider: a cooldown earned by one must not silence the other.
    public static string CodexRateLimitStatePath =>
        Path.Combine(AppDataDirectory, "codex-rate-limit.json");

    /// Written by scripts/claude-statusline-bridge.ps1, read here. Lives beside
    /// the app's own caches, under the user's own roaming profile.
    public static string ClaudeStatusLinePath =>
        Path.Combine(AppDataDirectory, "claude-statusline.json");

    public static string CodexAuthPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".codex", "auth.json");

    public static string ClaudeCredentialsPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".claude", ".credentials.json");
}
