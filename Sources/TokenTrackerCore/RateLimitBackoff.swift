import Foundation

/// Computes the Claude 429 cooldown.
///
/// On repeated rate limiting the cooldown grows exponentially (capped) with
/// additive jitter, so a client that keeps getting 429 backs off further each
/// time instead of retrying the shared per-account limit at a fixed interval.
/// The escalation is intentionally a floor: an explicit server `Retry-After`
/// longer than the computed value is always honored, and jitter is additive so
/// the result never dips below that instruction.
public enum RateLimitBackoff {
    /// Never wait less than this, even for a tiny or absent `Retry-After`.
    public static let minimumCooldown: TimeInterval = 120
    /// Ceiling for the exponential growth (a longer explicit `Retry-After` may exceed it).
    public static let maximumCooldown: TimeInterval = 1800
    /// Upper bound of the additive jitter, as a fraction of the base cooldown.
    public static let jitterFraction: Double = 0.2

    /// - Parameters:
    ///   - retryAfter: the server's `Retry-After` hint (or the headerless default), in seconds.
    ///   - failureCount: consecutive 429s already observed (0 for the first).
    ///   - jitter: fraction added on top; clamped to `0...jitterFraction`.
    /// - Returns: the cooldown in seconds, always `>= max(minimumCooldown, retryAfter)`.
    public static func cooldown(retryAfter: TimeInterval, failureCount: Int, jitter: Double) -> TimeInterval {
        let base = max(minimumCooldown, retryAfter)
        let boundedExponent = min(max(0, failureCount), 20)
        let grown = base * pow(2, Double(boundedExponent))
        // Cap the exponential growth, but never dip below an explicit longer wait.
        let escalated = max(base, min(maximumCooldown, grown))
        let clampedJitter = min(max(0, jitter), jitterFraction)
        return escalated + escalated * clampedJitter
    }
}
