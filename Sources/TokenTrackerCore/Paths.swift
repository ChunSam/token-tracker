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

    static var codexAuth: URL {
        home.appendingPathComponent(".codex/auth.json")
    }

    static var codexSessions: URL {
        home.appendingPathComponent(".codex/sessions")
    }

    static var claudeCredentials: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }
}
