import Foundation
import Observation
import ServiceManagement

/// Native SMAppService wrapper for managing Launch at Login without external dependencies.
@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool = false
    private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
