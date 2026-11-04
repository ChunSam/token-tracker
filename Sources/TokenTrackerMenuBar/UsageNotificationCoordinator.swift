import Foundation
import TokenTrackerCore
import UserNotifications

@MainActor
final class UsageNotificationCoordinator {
    private let settings: Settings
    private var deliveredAlertIDs = Set<String>()
    /// Each provider's last reading with numbers, for telling when a low window
    /// has refilled. Kept current while notifications are off, so turning them
    /// back on does not compare against a reading from hours ago.
    private var lastReadings: [Provider: ProviderUsage] = [:]

    init(settings: Settings) {
        self.settings = settings
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Starts from the snapshot cached before the last quit, so a window that ran
    /// low and reset while the app was not running is still reported.
    func seedReadings(from snapshot: UsageSnapshot?) {
        guard let snapshot else { return }
        lastReadings = UsageAlertEvaluator.lastReadings(lastReadings, updatedWith: snapshot)
    }

    func handleNotifications(
        for snapshot: UsageSnapshot,
        extraCandidates: [UsageAlertCandidate] = [],
        localizer: Localizer
    ) {
        let previousReadings = lastReadings
        lastReadings = UsageAlertEvaluator.lastReadings(previousReadings, updatedWith: snapshot)

        guard settings.notificationsEnabled else {
            deliveredAlertIDs.removeAll()
            return
        }

        let candidates = UsageAlertEvaluator.candidates(
            snapshot: snapshot,
            settings: alertSettings(),
            localizer: localizer
        ) + UsageAlertEvaluator.freedUpCandidates(
            previous: previousReadings,
            current: snapshot,
            settings: alertSettings(),
            localizer: localizer
        ) + extraCandidates
        let activeIDs = Set(candidates.map(\.id))
        deliveredAlertIDs.formIntersection(activeIDs)

        for candidate in candidates where !deliveredAlertIDs.contains(candidate.id) {
            sendNotification(candidate)
            deliveredAlertIDs.insert(candidate.id)
        }
    }

    /// Alerts that keep their own once-a-month record (`CostAlertEvaluator`), sent
    /// as they are.
    func deliver(_ alerts: [UsageAlertCandidate]) {
        alerts.forEach(sendNotification)
    }

    private func alertSettings() -> UsageAlertSettings {
        UsageAlertSettings(
            notificationsEnabled: settings.notificationsEnabled,
            fiveHourThreshold: settings.fiveHourAlertThreshold,
            sevenDayThreshold: settings.sevenDayAlertThreshold,
            resetWarningMinutes: settings.resetAlertMinutes,
            stalledAfter: UsageAlertEvaluator.stalledThreshold(refreshInterval: settings.refreshInterval)
        )
    }

    private func sendNotification(_ candidate: UsageAlertCandidate) {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "TokenTracker.\(candidate.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
