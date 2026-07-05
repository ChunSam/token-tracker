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
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Returns the persisted retry instant only while it is still in the future;
    /// an expired or missing record reads as `nil`.
    public func load() -> Date? {
        guard
            let data = try? Data(contentsOf: url),
            let record = try? decoder.decode(Record.self, from: data),
            record.retryAllowedAt.timeIntervalSinceNow > 0
        else {
            return nil
        }
        return record.retryAllowedAt
    }

    public func save(retryAllowedAt: Date) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(Record(retryAllowedAt: retryAllowedAt))
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

    private struct Record: Codable {
        let retryAllowedAt: Date
    }
}
