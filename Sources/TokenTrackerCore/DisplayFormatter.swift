import Foundation

public struct DisplayFormatter {
    public static func statusTitle(snapshot: UsageSnapshot?, mode: DisplayMode, labelStyle: ProviderLabelStyle = .abbreviation) -> String {
        guard let snapshot else { return "AI --" }

        switch mode {
        case .lowestRemaining:
            let candidates = [snapshot.claude, snapshot.codex].compactMap { usage -> Int? in
                displayPercent(usage)
            }
            guard let lowest = candidates.min() else { return "AI --" }
            return "AI \(lowest)%"
        case .both:
            return "\(providerLabel(.codex, style: labelStyle)) \(formatPercent(displayPercent(snapshot.codex))) · \(providerLabel(.claude, style: labelStyle)) \(formatPercent(displayPercent(snapshot.claude)))"
        case .codexOnly:
            return "\(providerLabel(.codex, style: labelStyle)) \(formatPercent(displayPercent(snapshot.codex)))"
        case .claudeOnly:
            return "\(providerLabel(.claude, style: labelStyle)) \(formatPercent(displayPercent(snapshot.claude)))"
        }
    }

    public static func detailLine(_ usage: ProviderUsage) -> String {
        "\(usage.provider.displayName): 5h \(formatPercent(usage.remainingPercent5h)), 7d \(formatPercent(usage.remainingPercent7d))"
    }

    public static func displayPercent(_ usage: ProviderUsage) -> Int? {
        if let sevenDay = usage.remainingPercent7d, sevenDay <= 10 {
            return sevenDay
        }
        return usage.remainingPercent5h ?? usage.remainingPercent7d
    }

    /// Warning emphasis is reserved for an actually low 7d window. Showing the
    /// 7d number merely because the 5h window is absent (the normal Codex state
    /// since OpenAI removed the 5h limit) must not read as a warning.
    public static func isSevenDayWarning(_ usage: ProviderUsage) -> Bool {
        guard let sevenDay = usage.remainingPercent7d else { return false }
        return sevenDay <= 10
    }

    /// Which window the forecast and sparkline surfaces should use: the 5h
    /// window when it reports, otherwise the 7d window (Codex's normal state
    /// since OpenAI removed the 5h limit — without the fallback Codex would
    /// have no forecast or sparkline at all).
    public static func preferredForecastWindow(_ usage: ProviderUsage) -> ForecastWindow {
        if usage.remainingPercent5h != nil { return .fiveHour }
        return usage.remainingPercent7d != nil ? .sevenDay : .fiveHour
    }

    public static func providerLabel(_ provider: Provider, style: ProviderLabelStyle) -> String {
        switch style {
        case .abbreviation:
            switch provider {
            case .codex: return "Cdx"
            case .claude: return "Cl"
            }
        case .icon:
            switch provider {
            case .codex: return "Codex"
            case .claude: return "Claude"
            }
        }
    }

    public static func formatPercent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)%"
    }

    public static func formatReset(_ date: Date?, localizer: Localizer = Localizer(language: .english)) -> String {
        guard let date else { return "--" }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return localizer.text(.now) }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
