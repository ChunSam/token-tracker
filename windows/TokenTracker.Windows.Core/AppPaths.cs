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

    /// The Admin APIs limit per organization, apart from the usage endpoints, so
    /// their cooldowns are kept apart too.
    public static string AdminCostRateLimitStatePath(Provider provider) =>
        Path.Combine(AppDataDirectory, provider.ToId() + "-cost-rate-limit.json");

    public static string CostCachePath =>
        Path.Combine(AppDataDirectory, "cost-cache.json");

    /// Both Admin keys, encrypted with DPAPI for the signed-in user.
    public static string AdminKeysPath =>
        Path.Combine(AppDataDirectory, "admin-keys.dat");

    /// Written by scripts/claude-statusline-bridge.ps1, read here. Lives beside
    /// the app's own caches, under the user's own roaming profile.
    public static string ClaudeStatusLinePath =>
        Path.Combine(AppDataDirectory, "claude-statusline.json");

    /// Where Claude Code is started to renew its token. Nothing ever answers its
    /// trust prompt here, so a launch stops at that prompt instead of running
    /// hooks, plugins or a session.
    public static string ClaudeCliRefreshDirectory =>
        Path.Combine(AppDataDirectory, "claude-cli-refresh");

    public static string CodexAuthPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".codex", "auth.json");

    public static string ClaudeCredentialsPath(string? homeDirectory = null) =>
        Path.Combine(homeDirectory ?? HomeDirectory, ".claude", ".credentials.json");
}
