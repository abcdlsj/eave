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

        // Also clear any previously tracked bundle ID that is no longer badged.
        for oldBundleID in previous.keys where current[oldBundleID] == nil && !cleared.contains(oldBundleID) {
            cleared.append(oldBundleID)
        }

        return DiffResult(
            newlyTriggered: triggered.sorted { $0.appName < $1.appName },
            clearedBundleIDs: cleared.sorted()
        )
    }

    /// Returns true if a badge changed to a higher unread count or a distinct non-decreasing label.
    static func shouldTriggerIncrease(from old: String, to new: String) -> Bool {
        guard old != new else { return false }
        if let oldInt = parseLeadingInt(old), let newInt = parseLeadingInt(new) {
            return newInt > oldInt
        }
        // Non-numeric badge change (e.g. "•" -> "1" or "New") triggers once.
        return !new.isEmpty
    }

    private static func parseLeadingInt(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }
}

/// Monitors Dock tile `AXStatusLabel` attributes via macOS Accessibility APIs.
/// Zero screen recording required; zero privacy indicator dot.
@MainActor
final class DockBadgeMonitor {
    private var timer: Timer?
    private var previousBadges: [String: String] = [:]
    private var isPrimed: Bool = false

    var watchedBundleIDsProvider: (() -> Set<String>)?
    var onBadgesChanged: ((DockBadgeDiffEngine.DiffResult, [String: DockBadgeSnapshot]) -> Void)?

    func start(interval: TimeInterval = 2.0) {
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
        guard AXIsProcessTrusted() else { return }
        let watched = watchedBundleIDsProvider?() ?? []
        let current = readCurrentDockBadges()

        // On first read, record existing badges without spamming peeks for already-unread apps.
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

    // MARK: - Accessibility Dock Traversal

    private func readCurrentDockBadges() -> [String: DockBadgeSnapshot] {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return [:]
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let children = copyChildren(of: dockElement) else { return [:] }

        var results: [String: DockBadgeSnapshot] = [:]
        for child in children {
            guard let listChildren = copyChildren(of: child) else { continue }
            for item in listChildren {
                guard let statusLabel = copyStringAttribute(item, attribute: "AXStatusLabel"),
                      !statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                let title = copyStringAttribute(item, attribute: kAXTitleAttribute) ?? "App"
                if let bundleID = resolveBundleIdentifier(for: item, fallbackTitle: title) {
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

    private func resolveBundleIdentifier(for dockItem: AXUIElement, fallbackTitle: String) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(dockItem, kAXURLAttribute as CFString, &value) == .success,
           let url = value as? URL,
           let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier {
            return id
        }

        // Fallback: match against currently running apps by localized name.
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(fallbackTitle) == .orderedSame
        }) {
            return app.bundleIdentifier
        }
        return nil
    }

    private func copyChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }
}
