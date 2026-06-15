import Foundation

public struct UsageAlertSettings: Equatable, Sendable {
    public let notificationsEnabled: Bool
    public let fiveHourThreshold: Int
    public let sevenDayThreshold: Int
    public let resetWarningMinutes: Int

    public init(notificationsEnabled: Bool, fiveHourThreshold: Int, sevenDayThreshold: Int, resetWarningMinutes: Int) {
        self.notificationsEnabled = notificationsEnabled
        self.fiveHourThreshold = max(0, min(100, fiveHourThreshold))
        self.sevenDayThreshold = max(0, min(100, sevenDayThreshold))
        self.resetWarningMinutes = max(0, resetWarningMinutes)
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
        if let remaining = usage.remainingPercent5h,
           settings.fiveHourThreshold > 0,
           remaining <= settings.fiveHourThreshold {
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
           remaining <= settings.sevenDayThreshold {
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
