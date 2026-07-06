import Foundation
import TokenTrackerCore
import UserNotifications

@MainActor
final class UsageNotificationCoordinator {
    private let settings: Settings
    private var deliveredAlertIDs = Set<String>()

    init(settings: Settings) {
        self.settings = settings
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handleNotifications(
        for snapshot: UsageSnapshot,
        extraCandidates: [UsageAlertCandidate] = [],
        localizer: Localizer
    ) {
        guard settings.notificationsEnabled else {
            deliveredAlertIDs.removeAll()
            return
        }

        let candidates = UsageAlertEvaluator.candidates(
            snapshot: snapshot,
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

    private func alertSettings() -> UsageAlertSettings {
        UsageAlertSettings(
            notificationsEnabled: settings.notificationsEnabled,
            fiveHourThreshold: settings.fiveHourAlertThreshold,
            sevenDayThreshold: settings.sevenDayAlertThreshold,
            resetWarningMinutes: settings.resetAlertMinutes
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
