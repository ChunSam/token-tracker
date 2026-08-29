import Foundation
#if canImport(Security)
import Security
#endif

/// Where the Claude access token actually came from, and when it was last written.
///
/// Diagnostics used to report only whether `~/.claude/.credentials.json` exists,
/// which reads `false` on a normal macOS install — the token lives in the keychain
/// and the file is a fallback. That hid the question that matters when usage stops
/// loading: *is anything still refreshing this token?*
///
/// The access token lives ~8h and only the Claude Code CLI (or its daemon, which
/// exits when idle) writes this store; the desktop app refreshes its own auth
/// elsewhere and leaves the keychain item untouched. So a modification date hours
/// or days old is the signal that the store has been abandoned, and the whole
/// answer to "why does it keep expiring".
///
/// Reads attributes only — never the secret.
public struct ClaudeCredentialSource: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case keychain
        case credentialsFile
        case none
    }

    public let kind: Kind
    public let lastWrittenAt: Date?

    public init(kind: Kind, lastWrittenAt: Date?) {
        self.kind = kind
        self.lastWrittenAt = lastWrittenAt
    }

    public static func detect(credentialsFileURL: URL) -> ClaudeCredentialSource {
        detect(credentialsFileURL: credentialsFileURL, keychainModifiedAt: keychainModificationDate())
    }

    /// Seam for tests: the keychain lookup is the one part that cannot be arranged
    /// on a build machine, and the precedence between the two stores is exactly what
    /// the old "does the file exist" line got wrong.
    public static func detect(credentialsFileURL: URL, keychainModifiedAt: Date?) -> ClaudeCredentialSource {
        if let keychainModifiedAt {
            return ClaudeCredentialSource(kind: .keychain, lastWrittenAt: keychainModifiedAt)
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: credentialsFileURL.path) {
            return ClaudeCredentialSource(
                kind: .credentialsFile,
                lastWrittenAt: attributes[.modificationDate] as? Date
            )
        }
        return ClaudeCredentialSource(kind: .none, lastWrittenAt: nil)
    }

    /// How stale the store is, which is what tells a lapsed token apart from a
    /// merely unlucky one: past roughly the 8h access-token life, nothing is
    /// refreshing it any more.
    public func age(now: Date = Date()) -> TimeInterval? {
        lastWrittenAt.map { now.timeIntervalSince($0) }
    }

    private static func keychainModificationDate() -> Date? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let attributes = item as? [String: Any]
        else {
            return nil
        }
        return attributes[kSecAttrModificationDate as String] as? Date
        #else
        return nil
        #endif
    }
}
