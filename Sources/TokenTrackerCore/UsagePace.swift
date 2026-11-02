import Foundation

/// How a window's spending compares with spreading it evenly up to the reset.
///
/// Half the window gone with 70% of it used is spending faster than the even
/// line. That takes one measurement and the reset time to say, where
/// `UsageForecaster` needs a run of stored history before it can project anything.
public enum UsagePace: Equatable, Sendable {
    /// Spending faster than the even line: at this rate the window runs out early.
    case ahead
    case onTrack
    /// Spending slower than the even line: there is room to spare before the reset.
    case behind
}

public struct UsagePaceReading: Equatable, Sendable {
    public let pace: UsagePace
    /// Where the remaining bar would stand had the window been used evenly up to
    /// the measurement.
    public let expectedRemainingPercent: Int

    public init(pace: UsagePace, expectedRemainingPercent: Int) {
        self.pace = pace
        self.expectedRemainingPercent = expectedRemainingPercent
    }
}

public enum UsagePaceEvaluator {
    /// Percentage points either side of the even line that still count as on
    /// track, so a few points of drift do not flip the label from poll to poll.
    public static let tolerance = 10

    /// Pace for one of a provider's windows, judged at the moment it was measured.
    ///
    /// A cached reading gets none: its percentage belongs to a moment the window
    /// has since moved on from, the same reason it gets no countdown.
    public static func reading(for usage: ProviderUsage, window: ForecastWindow) -> UsagePaceReading? {
        guard usage.source == .api || usage.source == .statusLine else { return nil }
        switch window {
        case .fiveHour:
            return reading(remainingPercent: usage.remainingPercent5h, resetAt: usage.resetAt5h, window: window, measuredAt: usage.updatedAt)
        case .sevenDay:
            return reading(remainingPercent: usage.remainingPercent7d, resetAt: usage.resetAt7d, window: window, measuredAt: usage.updatedAt)
        }
    }

    public static func reading(
        remainingPercent: Int?,
        resetAt: Date?,
        window: ForecastWindow,
        measuredAt: Date
    ) -> UsagePaceReading? {
        guard let remainingPercent, let resetAt else { return nil }
        let timeLeft = resetAt.timeIntervalSince(measuredAt)
        // Past its reset, or further off than the window is long: there is no
        // point in this window to compare against.
        guard timeLeft > 0, timeLeft <= window.duration else { return nil }

        let expected = 100 * timeLeft / window.duration
        let gap = Double(remainingPercent) - expected
        let pace: UsagePace
        if gap < -Double(tolerance) {
            pace = .ahead
        } else if gap > Double(tolerance) {
            pace = .behind
        } else {
            pace = .onTrack
        }
        return UsagePaceReading(pace: pace, expectedRemainingPercent: clampPercent(expected))
    }
}

public enum UsagePaceText {
    public static func label(_ pace: UsagePace, localizer: Localizer) -> String {
        switch pace {
        case .ahead: localizer.text(.paceAhead)
        case .onTrack: localizer.text(.paceOnTrack)
        case .behind: localizer.text(.paceBehind)
        }
    }

    /// `Pace: 5h ahead · 7d on track`, or `nil` when neither window has a pace.
    public static func menuLine(for usage: ProviderUsage, localizer: Localizer) -> String? {
        let parts = [ForecastWindow.fiveHour, .sevenDay].compactMap { window -> String? in
            guard let reading = UsagePaceEvaluator.reading(for: usage, window: window) else { return nil }
            return "\(window.shortLabel) \(label(reading.pace, localizer: localizer))"
        }
        guard !parts.isEmpty else { return nil }
        return "\(localizer.text(.pace)): \(parts.joined(separator: " · "))"
    }
}
