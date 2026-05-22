import Foundation

public struct DisplayFormatter {
    public static func statusTitle(snapshot: UsageSnapshot?, mode: DisplayMode) -> String {
        guard let snapshot else { return "AI --" }

        switch mode {
        case .lowestRemaining:
            let candidates = [snapshot.claude, snapshot.codex].compactMap { usage -> Int? in
                usage.remainingPercent5h
            }
            guard let lowest = candidates.min() else { return "AI --" }
            return "AI \(lowest)%"
        case .both:
            return "Cdx \(formatPercent(snapshot.codex.remainingPercent5h)) · Cl \(formatPercent(snapshot.claude.remainingPercent5h))"
        case .codexOnly:
            return "Cdx \(formatPercent(snapshot.codex.remainingPercent5h))"
        }
    }

    public static func detailLine(_ usage: ProviderUsage) -> String {
        "\(usage.provider.displayName): 5h \(formatPercent(usage.remainingPercent5h)), 7d \(formatPercent(usage.remainingPercent7d))"
    }

    public static func formatPercent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)%"
    }

    public static func formatReset(_ date: Date?) -> String {
        guard let date else { return "--" }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
