import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the preferences window can offer a
/// "Launch at login" toggle whose state always reflects what the system says.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var lastError: String?

    /// Both "never registered" and "user removed it in System Settings" read
    /// as off; "requires approval" counts as on because the user asked for it.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    /// A quarantined app launched from a random folder runs from a hidden
    /// translocated copy; registering that path would not survive a reboot.
    var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch let error as NSError {
            // Already in the requested state is not a failure.
            let benign = enabled ? Int(kSMErrorAlreadyRegistered) : Int(kSMErrorJobNotFound)
            if error.domain != "SMAppServiceErrorDomain" || error.code != benign {
                lastError = error.localizedDescription
            }
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
