import Foundation

public struct CodexRateWindow {
    public var usedPercent: Double?
    public var resetAt: Date?
    public var windowSeconds: Double?

    public init(usedPercent: Double?, resetAt: Date?, windowSeconds: Double?) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.windowSeconds = windowSeconds
    }
}

public struct CodexMappedWindows {
    public var fiveHour: CodexRateWindow?
    public var sevenDay: CodexRateWindow?

    public init(fiveHour: CodexRateWindow?, sevenDay: CodexRateWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Assigns the Codex API's rate-limit windows to the 5h/7d display lanes by
/// their advertised length instead of their position: since 2026-07 the API can
/// report the weekly window as `primary_window` (the 5h window was removed), so
/// positional mapping would show weekly usage in the 5h lane.
public enum CodexWindowMapper {
    /// Windows shorter than a day belong to the short-term (5h) lane; a day or
    /// longer is the weekly lane.
    static let laneBoundarySeconds: Double = 24 * 60 * 60

    public static func map(primary: CodexRateWindow?, secondary: CodexRateWindow?) -> CodexMappedWindows {
        var mapped = CodexMappedWindows(fiveHour: nil, sevenDay: nil)
        assign(primary, positionalLane: \.fiveHour, into: &mapped)
        assign(secondary, positionalLane: \.sevenDay, into: &mapped)
        return mapped
    }

    private static func assign(
        _ window: CodexRateWindow?,
        positionalLane: WritableKeyPath<CodexMappedWindows, CodexRateWindow?>,
        into mapped: inout CodexMappedWindows
    ) {
        guard let window else { return }
        let lane: WritableKeyPath<CodexMappedWindows, CodexRateWindow?>
        if let seconds = window.windowSeconds {
            lane = seconds < laneBoundarySeconds ? \.fiveHour : \.sevenDay
        } else {
            lane = positionalLane
        }
        if mapped[keyPath: lane] == nil {
            mapped[keyPath: lane] = window
        }
    }
}

public enum CodexUsageParser {
    public static func parse(object: [String: Any], updatedAt: Date = Date()) -> ProviderUsage? {
        guard let rateLimit = object["rate_limit"] as? [String: Any] else { return nil }
        let mapped = CodexWindowMapper.map(
            primary: window(rateLimit["primary_window"]),
            secondary: window(rateLimit["secondary_window"])
        )
        return ProviderUsage(
            provider: .codex,
            remainingPercent5h: remainingPercent(fromUsed: mapped.fiveHour?.usedPercent),
            remainingPercent7d: remainingPercent(fromUsed: mapped.sevenDay?.usedPercent),
            resetAt5h: mapped.fiveHour?.resetAt,
            resetAt7d: mapped.sevenDay?.resetAt,
            source: .api,
            error: nil,
            plan: object["plan_type"] as? String,
            model: nil,
            updatedAt: updatedAt
        )
    }

    private static func window(_ value: Any?) -> CodexRateWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        return CodexRateWindow(
            usedPercent: dict["used_percent"] as? Double,
            resetAt: timestampDate(dict["reset_at"]),
            windowSeconds: dict["limit_window_seconds"] as? Double
        )
    }
}
