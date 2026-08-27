import Foundation

enum AppPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
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
}
