import Foundation

public struct DisplayFormatter {
    public static func statusTitle(
        snapshot: UsageSnapshot?,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle = .abbreviation,
        showResetCountdown: Bool = false,
        localizer: Localizer = Localizer(language: .english)
    ) -> String {
        guard let snapshot else { return "AI --" }

        func countdown(_ usage: ProviderUsage?) -> String {
            resetCountdownSuffix(usage, showResetCountdown: showResetCountdown, localizer: localizer)
        }

        switch mode {
        case .lowestRemaining:
            guard let lowest = lowestUsage(snapshot), let percent = displayPercent(lowest) else {
                return "AI --"
            }
            return "AI \(percent)%\(countdown(lowest))"
        case .both:
            let codex = "\(providerLabel(.codex, style: labelStyle)) \(formatPercent(displayPercent(snapshot.codex)))\(countdown(snapshot.codex))"
            let claude = "\(providerLabel(.claude, style: labelStyle)) \(formatPercent(displayPercent(snapshot.claude)))\(countdown(snapshot.claude))"
            return "\(codex) · \(claude)"
        case .codexOnly:
            return "\(providerLabel(.codex, style: labelStyle)) \(formatPercent(displayPercent(snapshot.codex)))\(countdown(snapshot.codex))"
        case .claudeOnly:
            return "\(providerLabel(.claude, style: labelStyle)) \(formatPercent(displayPercent(snapshot.claude)))\(countdown(snapshot.claude))"
        }
    }

    public static func detailLine(_ usage: ProviderUsage) -> String {
        "\(usage.provider.displayName): 5h \(formatPercent(usage.remainingPercent5h)), 7d \(formatPercent(usage.remainingPercent7d))"
    }

    public static func displayPercent(_ usage: ProviderUsage) -> Int? {
        switch displayWindow(usage) {
        case .fiveHour: return usage.remainingPercent5h
        case .sevenDay: return usage.remainingPercent7d
        case nil: return nil
        }
    }

    /// Which window the menu bar percentage comes from. `displayPercent` reads its
    /// number from here so the countdown drawn beside it always names the reset
    /// that number is actually counting down to, rather than the two drifting apart.
    public static func displayWindow(_ usage: ProviderUsage) -> ForecastWindow? {
        if let sevenDay = usage.remainingPercent7d, sevenDay <= 10 {
            return .sevenDay
        }
        if usage.remainingPercent5h != nil {
            return .fiveHour
        }
        return usage.remainingPercent7d != nil ? .sevenDay : nil
    }

    public static func displayResetAt(_ usage: ProviderUsage) -> Date? {
        switch displayWindow(usage) {
        case .fiveHour: return usage.resetAt5h
        case .sevenDay: return usage.resetAt7d
        case nil: return nil
        }
    }

    /// The provider whose percentage `lowestRemaining` mode shows, so that mode can
    /// pair its number with the matching reset. Ties keep Claude, matching the order
    /// the status title and its warning colour already use.
    public static func lowestUsage(_ snapshot: UsageSnapshot) -> ProviderUsage? {
        [snapshot.claude, snapshot.codex]
            .compactMap { usage in displayPercent(usage).map { (usage, $0) } }
            .min { $0.1 < $1.1 }?
            .0
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

    /// Menu bar variant of `formatReset`: the same buckets without the inner space,
    /// because every character here costs menu bar width. Returns nil rather than
    /// `--` when there is no reset to show, so the caller appends nothing at all.
    public static func formatResetCompact(_ date: Date?, localizer: Localizer = Localizer(language: .english)) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return localizer.text(.now) }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h\(minutes % 60)m" }
        return "\(hours / 24)d\(hours % 24)h"
    }

    /// The countdown suffix for a provider's menu bar segment: a leading space plus
    /// the compact time, or an empty string when the countdown is off, the window is
    /// unknown, or the provider reported no reset instant.
    public static func resetCountdownSuffix(
        _ usage: ProviderUsage?,
        showResetCountdown: Bool,
        localizer: Localizer = Localizer(language: .english)
    ) -> String {
        guard showResetCountdown, let usage else { return "" }
        // A cached reading's reset instant keeps ticking down while the value behind
        // it stands still, and once it passes the countdown reads "now" for as long
        // as the fallback lasts. Show no time rather than a wrong one.
        guard usage.source == .api else { return "" }
        guard let text = formatResetCompact(displayResetAt(usage), localizer: localizer) else { return "" }
        return " \(text)"
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
