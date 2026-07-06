import Foundation

/// Pure helpers for the user-initiated "pause updates" state. A paused poll
/// skips the network fetch entirely, reducing the app's own contribution to the
/// shared per-account rate limit. The pause instant is persisted, so a restart
/// during a pause stays paused.
public enum PauseController {
    /// A pause farther out than this is treated as "until I resume" (no
    /// countdown shown) rather than a timed pause.
    public static let indefiniteThreshold: TimeInterval = 365 * 24 * 60 * 60

    public static func isPaused(until pausedUntil: Date?, now: Date = Date()) -> Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > now
    }

    public static func remaining(until pausedUntil: Date?, now: Date = Date()) -> TimeInterval {
        guard let pausedUntil, pausedUntil > now else { return 0 }
        return pausedUntil.timeIntervalSince(now)
    }

    public static func isIndefinite(until pausedUntil: Date?, now: Date = Date()) -> Bool {
        guard let pausedUntil else { return false }
        return pausedUntil.timeIntervalSince(now) > indefiniteThreshold
    }
}
