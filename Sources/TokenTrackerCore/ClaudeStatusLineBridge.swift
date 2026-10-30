import Foundation

/// A Claude usage reading that came from Claude Code's own status line, relayed
/// through a local file by `scripts/claude-statusline-bridge.sh`.
///
/// Token Tracker only *reads* the access token Claude Code stores; nothing here
/// refreshes it. Once that token lapses — which it does whenever the CLI has not
/// been run for a few hours — the API path has nothing usable to send and Claude
/// collection stops entirely until the user runs `/login` again. The status line
/// is the one documented input that reports the same two subscription windows
/// without this app touching a credential at all.
///
/// The hazard the format is built around: the status-line command re-runs on the
/// CLI's own schedule, so *being written again* is not evidence that the account
/// was measured again. The bridge therefore records two separate instants —
/// `measured_at`, which only moves when a window's numbers actually change, and
/// `written_at`, which moves on every run — and everything here ages a reading by
/// `measured_at`. A replayed payload keeps its original age and expires on time.
public struct ClaudeStatusLineRecord: Equatable, Sendable {
    /// When the reported numbers last changed. The age of the measurement.
    public let measuredAt: Date
    /// When the bridge last ran. Kept for diagnostics only — never for freshness.
    public let writtenAt: Date
    public let usedPercent5h: Double?
    public let resetAt5h: Date?
    public let usedPercent7d: Double?
    public let resetAt7d: Date?

    public init(
        measuredAt: Date,
        writtenAt: Date,
        usedPercent5h: Double?,
        resetAt5h: Date?,
        usedPercent7d: Double?,
        resetAt7d: Date?
    ) {
        self.measuredAt = measuredAt
        self.writtenAt = writtenAt
        self.usedPercent5h = usedPercent5h
        self.resetAt5h = resetAt5h
        self.usedPercent7d = usedPercent7d
        self.resetAt7d = resetAt7d
    }

    public func age(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(measuredAt)
    }
}

public enum ClaudeStatusLineBridge {
    /// Bumped only for a breaking change to the file the bridge writes; a record
    /// carrying anything else is ignored rather than guessed at.
    public static let version = 1

    /// How long a status-line measurement may stand in as a *current* reading.
    /// Matches `UsageForecaster.maximumSampleAge`, which is already this repo's
    /// answer to "how old may a sample be before it stops describing now". Past
    /// it the reading is handed to the ordinary stale-cache path, which labels it
    /// as cached instead of presenting it as the account's current state.
    public static let freshnessWindow: TimeInterval = 1800

    /// The bridge and the app can disagree slightly about the time. Allow that
    /// much before calling a timestamp impossible.
    public static let clockSkew: TimeInterval = 300

    /// Parse the bridge file. Returns `nil` for anything unusable — a missing or
    /// unknown version, no readable window, or a measurement stamped in the
    /// future, which cannot be aged honestly.
    public static func record(fromJSON data: Data, now: Date = Date()) -> ClaudeStatusLineRecord? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            number(object["version"]).map({ Int($0) }) == version,
            let measuredSeconds = number(object["measured_at"])
        else {
            return nil
        }

        let measuredAt = Date(timeIntervalSince1970: measuredSeconds)
        guard measuredAt.timeIntervalSince(now) <= clockSkew else {
            return nil
        }
        let writtenAt = number(object["written_at"]).map { Date(timeIntervalSince1970: $0) } ?? measuredAt

        let limits = object["rate_limits"] as? [String: Any]
        let fiveHour = window(limits?["five_hour"], now: now)
        let sevenDay = window(limits?["seven_day"], now: now)
        guard fiveHour != nil || sevenDay != nil else {
            return nil
        }

        return ClaudeStatusLineRecord(
            measuredAt: measuredAt,
            writtenAt: writtenAt,
            usedPercent5h: fiveHour?.usedPercent,
            resetAt5h: fiveHour?.resetAt,
            usedPercent7d: sevenDay?.usedPercent,
            resetAt7d: sevenDay?.resetAt
        )
    }

    /// The reading to show, or `nil` when there is nothing current to show. A
    /// stale record deliberately yields `nil` rather than a reading: the caller's
    /// existing cache policy then carries the last good value with its own
    /// "using cached data" label, instead of this presenting an old measurement
    /// as the live one.
    ///
    /// `apiError` is the reason the API path produced nothing, carried through so
    /// the menu can still say "sign in again" while showing these numbers.
    public static func usage(
        _ record: ClaudeStatusLineRecord?,
        apiError: String?,
        now: Date = Date()
    ) -> ProviderUsage? {
        guard let record else { return nil }
        let age = record.age(now: now)
        guard age <= freshnessWindow, age >= -clockSkew else { return nil }

        return ProviderUsage(
            provider: .claude,
            remainingPercent5h: remainingPercent(fromUsed: record.usedPercent5h),
            remainingPercent7d: remainingPercent(fromUsed: record.usedPercent7d),
            resetAt5h: record.resetAt5h,
            resetAt7d: record.resetAt7d,
            source: .statusLine,
            error: apiError,
            plan: nil,
            model: nil,
            // The measurement time, not now: a reading that is re-read on every
            // poll must keep aging, or the cache never expires.
            updatedAt: record.measuredAt
        )
    }

    private struct Window {
        let usedPercent: Double
        let resetAt: Date
    }

    /// Claude Code drops a window once its `resets_at` has passed, so a window
    /// still in the file whose reset is behind us describes a window instance
    /// that no longer exists. Both fields are required: without `resets_at` there
    /// is no way to tell a live window from an expired one.
    private static func window(_ raw: Any?, now: Date) -> Window? {
        guard
            let object = raw as? [String: Any],
            let used = number(object["used_percentage"]),
            let resetSeconds = number(object["resets_at"])
        else {
            return nil
        }
        let resetAt = Date(timeIntervalSince1970: resetSeconds)
        guard resetAt > now else { return nil }
        return Window(usedPercent: min(100, max(0, used)), resetAt: resetAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard
            let raw = value as? NSNumber,
            CFGetTypeID(raw) != CFBooleanGetTypeID(),
            raw.doubleValue.isFinite
        else {
            return nil
        }
        return raw.doubleValue
    }
}

/// Reads the bridge file. Separate from the parsing so the policy above stays a
/// pure function the smoke tests can drive without a filesystem.
public struct ClaudeStatusLineStore: Sendable {
    public let url: URL

    public init() {
        self.url = AppPaths.claudeStatusLine
    }

    public init(url: URL) {
        self.url = url
    }

    public func read(now: Date = Date()) -> ClaudeStatusLineRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ClaudeStatusLineBridge.record(fromJSON: data, now: now)
    }

    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
