import Foundation
import ServiceManagement
import TokenTrackerCore

@MainActor
final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func statusLabel(localizer: Localizer) -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return localizer.text(.statusEnabled)
        case .notRegistered:
            return localizer.text(.statusDisabled)
        case .notFound:
            return localizer.text(.statusNotFound)
        case .requiresApproval:
            return localizer.text(.statusRequiresApproval)
        @unknown default:
            return localizer.text(.statusUnknown)
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
