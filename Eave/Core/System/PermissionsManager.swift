import AppKit
import ApplicationServices
import Foundation
import Observation

/// Tracks optional macOS Accessibility permission required for hidden-app signals and click forwarding.
@MainActor
@Observable
final class PermissionsManager {
    private(set) var hasAccessibility: Bool = false

    private var pollTimer: Timer?

    init() {
        refresh()
    }

    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func startPolling(interval: TimeInterval = 2.5) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccessibilityPrompt() {
        // Use string key directly to stay clean under Swift 6 strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
