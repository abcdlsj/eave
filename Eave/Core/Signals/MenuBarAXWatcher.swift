import AppKit
import ApplicationServices
import Foundation

/// Monitors Accessibility text/description changes on hidden menu-bar-only applications
/// on a background utility task so cross-process AX IPC never stalls the UI thread.
@MainActor
final class MenuBarAXWatcher {
    private struct TargetApp: Sendable {
        let pid: pid_t
        let bundleID: String
        let appName: String
    }

    private var timer: Timer?
    private var lastSignatures: [String: String] = [:]
    private var isPrimed: Bool = false
    private var isPolling: Bool = false

    var watchedBundleIDsProvider: (() -> Set<String>)?
    var onStatusTextChanged: ((_ bundleID: String, _ appName: String, _ statusText: String) -> Void)?

    func start(interval: TimeInterval = 6.0) {
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
        guard !isPolling, AXIsProcessTrusted() else { return }
        let watched = watchedBundleIDsProvider?() ?? []
        guard !watched.isEmpty else { return }

        let targets: [TargetApp] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, watched.contains(id), app.activationPolicy != .regular else {
                return nil
            }
            return TargetApp(pid: app.processIdentifier, bundleID: id, appName: app.localizedName ?? id)
        }
        guard !targets.isEmpty else { return }

        isPolling = true
        Task { [weak self] in
            let snapshots = await Task.detached(priority: .utility) {
                targets.compactMap { target -> (TargetApp, String)? in
                    guard let sig = Self.readExtrasSignature(for: target.pid), !sig.isEmpty else { return nil }
                    return (target, sig)
                }
            }.value

            guard let self else { return }
            self.isPolling = false

            for (target, signature) in snapshots {
                if !self.isPrimed {
                    self.lastSignatures[target.bundleID] = signature
                    continue
                }
                if let previous = self.lastSignatures[target.bundleID], previous != signature {
                    self.lastSignatures[target.bundleID] = signature
                    self.onStatusTextChanged?(target.bundleID, target.appName, signature)
                } else if self.lastSignatures[target.bundleID] == nil {
                    self.lastSignatures[target.bundleID] = signature
                }
            }
            self.isPrimed = true
        }
    }

    private nonisolated static func readExtrasSignature(for pid: pid_t) -> String? {
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

    private nonisolated static func copyString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
