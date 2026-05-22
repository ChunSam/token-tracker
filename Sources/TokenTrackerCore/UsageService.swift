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
        let claudeResult = await (settings.claudeEnabled
            ? claudeClient.fetch()
            : ProviderUsage.unavailable(.claude, error: "Disabled"))
        let codexResult = await (settings.codexEnabled
            ? codexClient.fetch()
            : ProviderUsage.unavailable(.codex, error: "Disabled"))

        var snapshot = UsageSnapshot(
            claude: claudeResult,
            codex: codexResult,
            updatedAt: Date()
        )

        if let stale = cacheStore.load(maxAge: 3600) {
            if !snapshot.claude.isAvailable, stale.claude.isAvailable {
                snapshot.claude = markStale(stale.claude, error: snapshot.claude.error)
            }
            if !snapshot.codex.isAvailable, stale.codex.isAvailable {
                snapshot.codex = markStale(stale.codex, error: snapshot.codex.error)
            }
        }

        cacheStore.save(snapshot)
        return snapshot
    }

    private func markStale(_ usage: ProviderUsage, error: String?) -> ProviderUsage {
        var copy = usage
        copy.source = .staleCache
        copy.error = error
        copy.updatedAt = Date()
        return copy
    }
}
