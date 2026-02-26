import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    private(set) var isEnabled = false
    private(set) var statusDescription = "Unavailable"
    private(set) var lastError: String?

    init() {
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refreshStatus()
    }

    func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusDescription = "Enabled"
        case .requiresApproval:
            isEnabled = false
            statusDescription = "Needs approval in System Settings"
        case .notFound:
            isEnabled = false
            statusDescription = "Requires bundled app build"
        case .notRegistered:
            isEnabled = false
            statusDescription = "Disabled"
        @unknown default:
            isEnabled = false
            statusDescription = "Unknown"
        }
    }
}
