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
            stale: cacheStore.load(maxAge: TimeInterval(settings.staleToleranceHours) * 3600),
            claudeEnabled: claudeEnabled,
            codexEnabled: codexEnabled,
            maxAge: TimeInterval(settings.staleToleranceHours) * 3600
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
        updatedAt: Date = Date(),
        maxAge: TimeInterval = 12 * 3600
    ) -> UsageSnapshot {
        guard let stale else {
            return current
        }

        var snapshot = current

        if claudeEnabled, !snapshot.claude.isAvailable, canReuse(stale.claude, at: updatedAt, maxAge: maxAge) {
            snapshot.claude = markStale(stale.claude, error: snapshot.claude.error)
        }

        if codexEnabled, !snapshot.codex.isAvailable, canReuse(stale.codex, at: updatedAt, maxAge: maxAge) {
            snapshot.codex = markStale(stale.codex, error: snapshot.codex.error)
        }

        return snapshot
    }

    private static func canReuse(_ usage: ProviderUsage, at now: Date, maxAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(usage.updatedAt)
        return usage.isAvailable && usage.source != .unavailable && age >= 0 && age <= maxAge
    }

    private static func markStale(_ usage: ProviderUsage, error: String?) -> ProviderUsage {
        var copy = usage
        copy.source = .staleCache
        copy.error = error
        // Keep the measurement time; redisplaying a value does not refresh it.
        return copy
    }
}
