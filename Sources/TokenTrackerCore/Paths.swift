import Foundation

enum AppPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        // The app was called Token Tracker before it became Tokki. The folder keeps
        // that name so existing caches, history and the status-line file stay put.
        return base.appendingPathComponent("Token Tracker", isDirectory: true)
    }

    static var snapshotCache: URL {
        cacheDirectory.appendingPathComponent("usage-cache.json")
    }

    static var usageHistory: URL {
        cacheDirectory.appendingPathComponent("usage-history.json")
    }

    static var claudeRateLimit: URL {
        cacheDirectory.appendingPathComponent("claude-rate-limit.json")
    }

    static var codexRateLimit: URL {
        cacheDirectory.appendingPathComponent("codex-rate-limit.json")
    }

    /// The Admin APIs limit per organization, apart from the usage endpoints, so
    /// their cooldowns are kept apart too.
    static func adminCostRateLimit(_ provider: Provider) -> URL {
        cacheDirectory.appendingPathComponent("\(provider.rawValue)-cost-rate-limit.json")
    }

    static var costCache: URL {
        cacheDirectory.appendingPathComponent("cost-cache.json")
    }

    /// Written by `scripts/claude-statusline-bridge.sh`, read here. Lives beside
    /// the app's own caches so it inherits the owner-only directory.
    static var claudeStatusLine: URL {
        cacheDirectory.appendingPathComponent("claude-statusline.json")
    }

    /// Where Claude Code is started to renew its token. Nothing ever answers its
    /// trust prompt here, so a launch stops at that prompt instead of running
    /// hooks, plugins or a session.
    static var claudeCLIRefreshDirectory: URL {
        cacheDirectory.appendingPathComponent("claude-cli-refresh", isDirectory: true)
    }

    static var codexAuth: URL {
        home.appendingPathComponent(".codex/auth.json")
    }

    static var claudeCredentials: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }
}

/// The cooldown files are per provider so a limit on one cannot silence the other.
/// Exposed for the smoke tests, which cannot see `AppPaths` across the module line.
public enum AppPathsProbe {
    public static var claudeRateLimitPath: String { AppPaths.claudeRateLimit.path }
    public static var codexRateLimitPath: String { AppPaths.codexRateLimit.path }
    public static var claudeStatusLinePath: String { AppPaths.claudeStatusLine.path }
}
