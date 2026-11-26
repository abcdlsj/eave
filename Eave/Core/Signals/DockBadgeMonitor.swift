import AppKit
import ApplicationServices
import Foundation

/// Snapshot of a single Dock application badge.
struct DockBadgeSnapshot: Equatable, Sendable {
    let bundleIdentifier: String
    let appName: String
    let badge: String
}

/// Pure diff engine separating Dock badge transition rules from AX polling for unit testing.
enum DockBadgeDiffEngine {
    struct DiffResult: Equatable, Sendable {
        let newlyTriggered: [DockBadgeSnapshot]
        let clearedBundleIDs: [String]
    }

    /// Computes which watched apps should trigger a Notch Peek and which cleared their badge.
    static func diff(
        previous: [String: String],
        current: [String: DockBadgeSnapshot],
        watchedBundleIDs: Set<String>
    ) -> DiffResult {
        var triggered: [DockBadgeSnapshot] = []
        var cleared: [String] = []

        for bundleID in watchedBundleIDs {
            let oldBadge = previous[bundleID]
            let newSnapshot = current[bundleID]

            switch (oldBadge, newSnapshot) {
            case (nil, let snap?):
                triggered.append(snap)
            case (let old?, let snap?):
                if shouldTriggerIncrease(from: old, to: snap.badge) {
                    triggered.append(snap)
                }
            case (_?, nil):
                cleared.append(bundleID)
            case (nil, nil):
                break
            }
        }

        for oldBundleID in previous.keys where current[oldBundleID] == nil && !cleared.contains(oldBundleID) {
            cleared.append(oldBundleID)
        }

        return DiffResult(
            newlyTriggered: triggered.sorted { $0.appName < $1.appName },
            clearedBundleIDs: cleared.sorted()
        )
    }

    static func shouldTriggerIncrease(from old: String, to new: String) -> Bool {
        guard old != new else { return false }
        if let oldInt = parseLeadingInt(old), let newInt = parseLeadingInt(new) {
            return newInt > oldInt
        }
        return !new.isEmpty
    }

    private static func parseLeadingInt(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }
}

/// Monitors Dock tile `AXStatusLabel` attributes via macOS Accessibility APIs on a background utility task
/// so Dock IPC never blocks the main UI thread.
@MainActor
final class DockBadgeMonitor {
    private var timer: Timer?
    private var previousBadges: [String: String] = [:]
    private var isPrimed: Bool = false
    private var isPolling: Bool = false

    var watchedBundleIDsProvider: (() -> Set<String>)?
    var onBadgesChanged: ((DockBadgeDiffEngine.DiffResult, [String: DockBadgeSnapshot]) -> Void)?

    func start(interval: TimeInterval = 3.0) {
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

    func poll() {
        guard !isPolling else { return }
        guard AXIsProcessTrusted() else {
            // Permission revoked at runtime: drop stale badges once so the Second Row stops showing them.
            if isPrimed || !previousBadges.isEmpty {
                isPrimed = false
                previousBadges = [:]
                onBadgesChanged?(DockBadgeDiffEngine.DiffResult(newlyTriggered: [], clearedBundleIDs: []), [:])
            }
            return
        }
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return
        }

        let watched = watchedBundleIDsProvider?() ?? []
        let runningNameMap: [String: String] = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard let name = app.localizedName?.lowercased(), let id = app.bundleIdentifier else { return nil }
                return (name, id)
            },
            uniquingKeysWith: { first, _ in first }
        )

        isPolling = true
        Task { [weak self] in
            let current = await Task.detached(priority: .utility) {
                Self.readCurrentDockBadges(dockPID: dockPID, runningNameMap: runningNameMap)
            }.value
            guard let self else { return }
            self.isPolling = false
            // A failed Dock read (Dock restarting, AX timeout) is not an empty Dock; skip this round
            // instead of treating it as "all badges cleared" and re-firing every badge next time.
            guard let current else { return }
            self.processPollResult(current: current, watched: watched)
        }
    }

    private func processPollResult(current: [String: DockBadgeSnapshot], watched: Set<String>) {
        if !isPrimed {
            isPrimed = true
            previousBadges = current.mapValues(\.badge)
            let initialActive = current.filter { watched.contains($0.key) }
            if !initialActive.isEmpty {
                onBadgesChanged?(DockBadgeDiffEngine.DiffResult(newlyTriggered: [], clearedBundleIDs: []), initialActive)
            }
            return
        }

        let result = DockBadgeDiffEngine.diff(
            previous: previousBadges,
            current: current,
            watchedBundleIDs: watched
        )
        previousBadges = current.mapValues(\.badge)

        if !result.newlyTriggered.isEmpty || !result.clearedBundleIDs.isEmpty {
            onBadgesChanged?(result, current)
        }
    }

    // MARK: - Background Accessibility Dock Traversal

    private nonisolated static func readCurrentDockBadges(
        dockPID: pid_t,
        runningNameMap: [String: String]
    ) -> [String: DockBadgeSnapshot]? {
        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 0.5)
        guard let children = copyChildren(of: dockElement) else { return nil }

        var results: [String: DockBadgeSnapshot] = [:]
        for child in children {
            guard let listChildren = copyChildren(of: child) else { continue }
            for item in listChildren {
                guard let statusLabel = copyStringAttribute(item, attribute: "AXStatusLabel"),
                      !statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                let title = copyStringAttribute(item, attribute: kAXTitleAttribute) ?? "App"
                if let bundleID = resolveBundleIdentifier(for: item, fallbackTitle: title, runningNameMap: runningNameMap) {
                    results[bundleID] = DockBadgeSnapshot(
                        bundleIdentifier: bundleID,
                        appName: title,
                        badge: statusLabel
                    )
                }
            }
        }
        return results
    }

    private nonisolated static func resolveBundleIdentifier(
        for dockItem: AXUIElement,
        fallbackTitle: String,
        runningNameMap: [String: String]
    ) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(dockItem, kAXURLAttribute as CFString, &value) == .success,
           let url = value as? URL,
           let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier {
            return id
        }
        return runningNameMap[fallbackTitle.lowercased()]
    }

    private nonisolated static func copyChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    private nonisolated static func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }
}
