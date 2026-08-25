import Foundation

/// Both providers store a short-lived OAuth access token that only their own CLI
/// refreshes; Token Tracker just reads it. Sending an already-expired token to the
/// usage endpoint returns something opaque and, for Anthropic, actively harmful:
/// `/api/oauth/usage` answers `429` for repeated expired-token requests, which the
/// rate-limit backoff then treats as a real quota cooldown and keeps blocking
/// refreshes long after the user has signed in again. Checking the expiry locally
/// lets the app report "sign in again" instead of an unactionable HTTP code.
public enum CredentialExpiry {
    /// Treat a token as expired slightly early so one that lapses between the check
    /// and the response is still reported as expired rather than as an HTTP error.
    public static let skew: TimeInterval = 60

    public static func isExpired(_ expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else {
            return false
        }
        return expiresAt.timeIntervalSince(now) <= skew
    }

    /// Reads the `exp` claim out of a JWT without verifying the signature. The
    /// provider remains the authority on whether a token is good; this only avoids
    /// spending a request on one that is already known to be stale.
    public static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard
            parts.count >= 2,
            let payload = base64URLDecoded(String(parts[1])),
            let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let exp = json["exp"] as? Double
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    /// Milliseconds-since-epoch is how Claude Code records `expiresAt`.
    public static func epochMillisecondsDate(_ value: Any?) -> Date? {
        let milliseconds: Double
        if let number = value as? Double {
            milliseconds = number
        } else if let number = value as? Int {
            milliseconds = Double(number)
        } else {
            return nil
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var text = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        return Data(base64Encoded: text)
    }
}

/// Stable, non-reversible fingerprint of the credentials a cooldown was recorded
/// against, so "the user signed in again" can be told apart from "same token, keep
/// waiting". Not a security boundary — it only has to change when the token does.
public enum TokenFingerprint {
    public static func of(_ tokens: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in tokens.sorted().joined(separator: "\u{0}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
