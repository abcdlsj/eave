import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Forwards clicks from the Notch Bar or Quick Search back to the real macOS menu bar status item.
/// Prefers `AXPress` (non-intrusive, cursor-free) and falls back to a synthetic `CGEvent` click.
@MainActor
final class MenuBarClickForwarder {
    private let menuBarManager: MenuBarManager
    private let scanner: MenuBarItemScanner

    init(menuBarManager: MenuBarManager, scanner: MenuBarItemScanner) {
        self.menuBarManager = menuBarManager
        self.scanner = scanner
    }

    func trigger(_ item: MenuBarItemInfo) async {
        let needsExpand = item.section != .visible && !menuBarManager.isHiddenExpanded
        let needsAlwaysExpand = item.section == .alwaysHidden && !menuBarManager.isAlwaysHiddenExpanded

        if needsExpand || needsAlwaysExpand {
            menuBarManager.expandHidden(includeAlwaysHidden: item.section == .alwaysHidden)
            // Allow WindowServer one brief layout frame to reposition the status items on screen.
            try? await Task.sleep(nanoseconds: 90_000_000)
        }

        // Strategy 1: Direct Accessibility AXPress (cleanest on macOS 15–26).
        if AXIsProcessTrusted(), performAXPress(for: item) {
            menuBarManager.postponeAutoRehide()
            return
        }

        // Strategy 2: Re-scan live screen coordinate off-main and synthesize a quick click, restoring cursor.
        let refreshed = await scanner.scanAsync(
            hiddenSeparatorX: menuBarManager.hiddenSeparatorX,
            alwaysHiddenSeparatorX: menuBarManager.alwaysHiddenSeparatorX,
            excludingWindowIDs: menuBarManager.ownedWindowIDs
        )
        let targetFrame = refreshed.first(where: {
            ($0.windowID != 0 && $0.windowID == item.windowID) ||
            ($0.pid == item.pid && $0.title == item.title)
        })?.frame ?? item.frame

        if targetFrame.width > 0 && targetFrame.minX >= 0 {
            postSyntheticClick(at: CGPoint(x: targetFrame.midX, y: targetFrame.midY))
            menuBarManager.postponeAutoRehide()
            return
        }

        // Strategy 3: If item couldn't be clicked directly (e.g. missing Accessibility permission),
        // activate the owning application so the user still gets an immediate response.
        if let app = NSRunningApplication(processIdentifier: item.pid) {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func performAXPress(for item: MenuBarItemInfo) -> Bool {
        let appElement = AXUIElementCreateApplication(item.pid)
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extrasRef else {
            return false
        }

        let extrasBar = extrasRef as! AXUIElement
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else {
            return false
        }

        // Match closest AX menu bar item by title or horizontal coordinate.
        let bestTarget = children.first(where: { child in
            if !item.title.isEmpty {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String, t == item.title {
                    return true
                }
            }
            return false
        }) ?? children.first

        guard let target = bestTarget else { return false }
        let err = AXUIElementPerformAction(target, kAXPressAction as CFString)
        return err == .success
    }

    private func postSyntheticClick(at point: CGPoint) {
        let originalLocation = CGEvent(source: nil)?.location

        guard let source = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        if let originalLocation,
           let restore = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: originalLocation, mouseButton: .left) {
            restore.post(tap: .cghidEventTap)
        }
    }
}
