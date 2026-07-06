import Foundation

/// Persists the Claude usage endpoint's 429 cooldown across app restarts.
///
/// The `/api/oauth/usage` rate limit is enforced per account and shared with
/// everything using the same OAuth token (Claude Code, duplicate menu-bar
/// instances, the Windows build). Keeping the cooldown in memory meant that
/// quitting and relaunching during a cooldown immediately fired a fresh request
/// that was still rate limited. Persisting the "retry allowed at" instant lets a
/// restarted app honor the outstanding cooldown instead of re-triggering 429.
public struct ClaudeRateLimitStore: Sendable {
    /// A persisted 429 cooldown: when the app may retry, and how many consecutive
    /// failures preceded it so exponential backoff survives a restart.
    public struct State: Sendable, Equatable {
        public let retryAllowedAt: Date
        public let failureCount: Int

        public init(retryAllowedAt: Date, failureCount: Int) {
            self.retryAllowedAt = retryAllowedAt
            self.failureCount = failureCount
        }
    }

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Returns the persisted cooldown only while its retry instant is still in the
    /// future; an expired or missing record reads as `nil`.
    public func load() -> State? {
        guard
            let data = try? Data(contentsOf: url),
            let record = try? decoder.decode(Record.self, from: data),
            record.retryAllowedAt.timeIntervalSinceNow > 0
        else {
            return nil
        }
        return State(retryAllowedAt: record.retryAllowedAt, failureCount: max(0, record.failureCount ?? 0))
    }

    public func save(_ state: State) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(Record(retryAllowedAt: state.retryAllowedAt, failureCount: state.failureCount))
            try data.write(to: url, options: .atomic)
            // Atomic writes replace the file via a temp file, so re-apply owner-only
            // permissions after each write rather than relying on the umask default.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    // `failureCount` is optional so a legacy record written before backoff was
    // persisted (retry instant only) still decodes, defaulting to 0.
    private struct Record: Codable {
        let retryAllowedAt: Date
        let failureCount: Int?
    }
}
