import Foundation

public struct UsageAlertSettings: Equatable, Sendable {
    public let notificationsEnabled: Bool
    public let fiveHourThreshold: Int
    public let sevenDayThreshold: Int
    public let resetWarningMinutes: Int
    /// How long a cached reading may stand before it is reported as stalled.
    /// Zero disables the alert, matching the other thresholds here.
    public let stalledAfter: TimeInterval

    public init(
        notificationsEnabled: Bool,
        fiveHourThreshold: Int,
        sevenDayThreshold: Int,
        resetWarningMinutes: Int,
        stalledAfter: TimeInterval = 0
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.fiveHourThreshold = max(0, min(100, fiveHourThreshold))
        self.sevenDayThreshold = max(0, min(100, sevenDayThreshold))
        self.resetWarningMinutes = max(0, resetWarningMinutes)
        self.stalledAfter = max(0, stalledAfter)
    }
}

public struct UsageAlertCandidate: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public enum UsageAlertEvaluator {
    public static func candidates(
        snapshot: UsageSnapshot,
        settings: UsageAlertSettings,
        now: Date = Date(),
        localizer: Localizer = Localizer(language: .english)
    ) -> [UsageAlertCandidate] {
        guard settings.notificationsEnabled else {
            return []
        }

        return Provider.allCases.flatMap { provider in
            let usage = snapshot.usage(for: provider)
            return candidates(
                for: usage,
                settings: settings,
                now: now,
                localizer: localizer
            )
        }
    }

    private static func candidates(
        for usage: ProviderUsage,
        settings: UsageAlertSettings,
        now: Date,
        localizer: Localizer
    ) -> [UsageAlertCandidate] {
        guard usage.isAvailable else {
            return []
        }

        var alerts: [UsageAlertCandidate] = []
        // First, because it says how much the numbers below it are still worth.
        if let stalled = stalledAlert(for: usage, settings: settings, now: now, localizer: localizer) {
            alerts.append(stalled)
        }

        if let remaining = usage.remainingPercent5h,
           settings.fiveHourThreshold > 0,
           remaining <= settings.fiveHourThreshold,
           !windowHasReset(usage.resetAt5h, now: now) {
            alerts.append(
                UsageAlertCandidate(
                    id: "\(usage.provider.rawValue)-5h-low",
                    title: localizer.text(.fiveHourAlertTitle),
                    body: "\(usage.provider.displayName) 5h \(remaining)% <= \(settings.fiveHourThreshold)%"
                )
            )
        }

        if let remaining = usage.remainingPercent7d,
           settings.sevenDayThreshold > 0,
           remaining <= settings.sevenDayThreshold,
           !windowHasReset(usage.resetAt7d, now: now) {
            alerts.append(
                UsageAlertCandidate(
                    id: "\(usage.provider.rawValue)-7d-low",
                    title: localizer.text(.sevenDayAlertTitle),
                    body: "\(usage.provider.displayName) 7d \(remaining)% <= \(settings.sevenDayThreshold)%"
                )
            )
        }

        alerts.append(contentsOf: resetAlerts(for: usage, settings: settings, now: now, localizer: localizer))
        return alerts
    }

    /// A balance only ever describes the window it was measured in. Once that
    /// window's reset has passed, the number on hand belongs to a window that has
    /// already refilled, so it is no reason to warn — and a cached reading can sit
    /// on the wrong side of a reset for hours. `resetCountdownSuffix` makes the
    /// same call about a cached reading's time; this keeps the alerts in step.
    ///
    /// With no reset instant to judge by there is nothing to go on, so the alert
    /// stands.
    private static func windowHasReset(_ resetAt: Date?, now: Date) -> Bool {
        guard let resetAt else { return false }
        return resetAt <= now
    }

    /// How long a cached reading may stand before the menu bar is quietly out of
    /// date: three missed polls, so one failed fetch is not news, with a floor of
    /// 30 minutes — the same freshness bound the status line bridge uses, and
    /// short enough to catch a lapsed token within the hour.
    public static func stalledThreshold(refreshInterval: TimeInterval) -> TimeInterval {
        max(30 * 60, refreshInterval * 3)
    }

    /// Collection has stalled: what is on screen is a cached measurement that has
    /// aged past `stalledAfter`. Nothing else alerts on this, so a lapsed token
    /// went unnoticed for as long as nobody looked — a cached percentage stays
    /// plausible while it quietly stops being current.
    ///
    /// A provider with nothing to show at all is deliberately left alone. It
    /// already reads as `--`, which cannot be mistaken for a live number, and
    /// alerting there would fire on the first failed fetch for a provider that
    /// was never signed in to.
    private static func stalledAlert(
        for usage: ProviderUsage,
        settings: UsageAlertSettings,
        now: Date,
        localizer: Localizer
    ) -> UsageAlertCandidate? {
        guard settings.stalledAfter > 0, usage.source == .staleCache else { return nil }
        let age = now.timeIntervalSince(usage.updatedAt)
        guard age > settings.stalledAfter else { return nil }
        let minutes = max(0, Int(age / 60))
        let ago = minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(minutes % 60)m"
        // A stable id: one alert per outage, and the coordinator drops the id once
        // the provider measures again, so the next outage is reported afresh.
        return UsageAlertCandidate(
            id: "\(usage.provider.rawValue)-stalled",
            title: localizer.text(.stalledAlertTitle),
            body: "\(usage.provider.displayName) last measured \(ago) ago"
        )
    }

    private static func resetAlerts(
        for usage: ProviderUsage,
        settings: UsageAlertSettings,
        now: Date,
        localizer: Localizer
    ) -> [UsageAlertCandidate] {
        guard settings.resetWarningMinutes > 0 else {
            return []
        }

        let warningWindow = TimeInterval(settings.resetWarningMinutes * 60)
        let resets: [(label: String, date: Date?)] = [
            ("5h", usage.resetAt5h),
            ("7d", usage.resetAt7d)
        ]

        return resets.compactMap { reset in
            guard let date = reset.date else {
                return nil
            }
            let remaining = date.timeIntervalSince(now)
            guard remaining > 0, remaining <= warningWindow else {
                return nil
            }
            let minutes = max(0, Int(ceil(remaining / 60)))
            let resetID = Int(date.timeIntervalSince1970)
            return UsageAlertCandidate(
                id: "\(usage.provider.rawValue)-\(reset.label)-reset-\(resetID)",
                title: localizer.text(.resetAlertTitle),
                body: "\(usage.provider.displayName) \(reset.label) reset in \(minutes)m"
            )
        }
    }
}

extension UsageSnapshot {
    public func usage(for provider: Provider) -> ProviderUsage {
        switch provider {
        case .claude:
            return claude
        case .codex:
            return codex
        }
    }
}
