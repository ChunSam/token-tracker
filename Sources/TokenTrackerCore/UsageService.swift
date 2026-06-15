import Foundation

@MainActor
public final class UsageService {
    private let settings: Settings
    private let cacheStore: CacheStore
    private let claudeClient: ClaudeUsageClient
    private let codexClient: CodexUsageClient

    public convenience init(settings: Settings) {
        self.init(
            settings: settings,
            cacheStore: CacheStore(),
            claudeClient: ClaudeUsageClient(),
            codexClient: CodexUsageClient()
        )
    }

    init(settings: Settings, cacheStore: CacheStore, claudeClient: ClaudeUsageClient, codexClient: CodexUsageClient) {
        self.settings = settings
        self.cacheStore = cacheStore
        self.claudeClient = claudeClient
        self.codexClient = codexClient
    }

    public func refresh() async -> UsageSnapshot {
        let claudeEnabled = settings.claudeEnabled
        let codexEnabled = settings.codexEnabled
        let claudeClient = self.claudeClient
        let codexClient = self.codexClient

        async let claudeResult: ProviderUsage = claudeEnabled
            ? claudeClient.fetch()
            : ProviderUsage.unavailable(.claude, error: "Disabled")
        async let codexResult: ProviderUsage = codexEnabled
            ? codexClient.fetch()
            : ProviderUsage.unavailable(.codex, error: "Disabled")

        var snapshot = UsageSnapshot(
            claude: await claudeResult,
            codex: await codexResult,
            updatedAt: Date()
        )

        snapshot = UsageSnapshotCachePolicy.apply(
            current: snapshot,
            stale: cacheStore.load(maxAge: 3600),
            claudeEnabled: claudeEnabled,
            codexEnabled: codexEnabled
        )

        cacheStore.save(snapshot)
        return snapshot
    }
}

public enum UsageSnapshotCachePolicy {
    public static func apply(
        current: UsageSnapshot,
        stale: UsageSnapshot?,
        claudeEnabled: Bool = true,
        codexEnabled: Bool = true,
        updatedAt: Date = Date()
    ) -> UsageSnapshot {
        guard let stale else {
            return current
        }

        var snapshot = current

        if claudeEnabled, !snapshot.claude.isAvailable, stale.claude.isAvailable {
            snapshot.claude = markStale(stale.claude, error: snapshot.claude.error, updatedAt: updatedAt)
        }

        if codexEnabled, !snapshot.codex.isAvailable, stale.codex.isAvailable {
            snapshot.codex = markStale(stale.codex, error: snapshot.codex.error, updatedAt: updatedAt)
        }

        return snapshot
    }

    private static func markStale(_ usage: ProviderUsage, error: String?, updatedAt: Date) -> ProviderUsage {
        var copy = usage
        copy.source = .staleCache
        copy.error = error
        copy.updatedAt = updatedAt
        return copy
    }
}
