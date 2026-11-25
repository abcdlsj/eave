import AppKit
import ApplicationServices
import Foundation

/// Monitors Accessibility text/description changes on hidden menu-bar-only applications
/// (apps without Dock icons, such as VPNs, proxies, timers, or sync agents).
@MainActor
final class MenuBarAXWatcher {
    private var timer: Timer?
    private var lastSignatures: [String: String] = [:]
    private var isPrimed: Bool = false

    var watchedBundleIDsProvider: (() -> Set<String>)?
    var onStatusTextChanged: ((_ bundleID: String, _ appName: String, _ statusText: String) -> Void)?

    func start(interval: TimeInterval = 4.0) {
        stop()
        isPrimed = false
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return }
        let watched = watchedBundleIDsProvider?() ?? []
        guard !watched.isEmpty else { return }

        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier, watched.contains(id) else { return false }
            // Focus on background / accessory apps whose state lives primarily in the menu bar.
            return app.activationPolicy != .regular
        }

        for app in running {
            guard let bundleID = app.bundleIdentifier else { continue }
            guard let signature = readExtrasSignature(for: app.processIdentifier), !signature.isEmpty else {
                continue
            }

            if !isPrimed {
                lastSignatures[bundleID] = signature
                continue
            }

            if let previous = lastSignatures[bundleID], previous != signature {
                lastSignatures[bundleID] = signature
                onStatusTextChanged?(bundleID, app.localizedName ?? bundleID, signature)
            } else if lastSignatures[bundleID] == nil {
                lastSignatures[bundleID] = signature
            }
        }

        isPrimed = true
    }

    private func readExtrasSignature(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extrasRef else {
            return nil
        }

        let extrasElement = extrasRef as! AXUIElement
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extrasElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        let parts: [String] = children.compactMap { item in
            let title = copyString(item, kAXTitleAttribute)
            let desc = copyString(item, kAXDescriptionAttribute)
            let value = copyString(item, kAXValueAttribute)
            let combined = [title, desc, value]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return combined.isEmpty ? nil : combined
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func copyString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
