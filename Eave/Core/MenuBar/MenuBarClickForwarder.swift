import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Dispatches interactions from the Second-Row Bar or Quick Search to target applications.
/// - Regular windowed apps (left click): activated directly without touching or expanding the menu bar.
/// - Menu-bar-only utilities or right-clicks: transiently reveal the menu bar item, prefer Accessibility
///   (`AXPress` / `AXShowMenu`), and fall back to a synthetic left/right `CGEvent` click.
@MainActor
final class MenuBarClickForwarder {
    enum ClickDispatchStrategy: Equatable, Sendable {
        case activateApp
        case forwardMenuBarItem(button: MenuBarClickButton)
    }

    private let menuBarManager: MenuBarManager
    private let scanner: MenuBarItemScanner

    init(menuBarManager: MenuBarManager, scanner: MenuBarItemScanner) {
        self.menuBarManager = menuBarManager
        self.scanner = scanner
    }

    /// Pure routing policy isolated for deterministic unit testing.
    nonisolated static func resolveStrategy(
        activationPolicy: NSApplication.ActivationPolicy?,
        button: MenuBarClickButton,
        preferAppActivationForRegularApps: Bool
    ) -> ClickDispatchStrategy {
        if preferAppActivationForRegularApps,
           button == .left,
           activationPolicy == .regular {
            return .activateApp
        }
        return .forwardMenuBarItem(button: button)
    }

    func trigger(
        _ item: MenuBarItemInfo,
        button: MenuBarClickButton = .left,
        preferAppActivationForRegularApps: Bool = true
    ) async {
        let runningApp = NSRunningApplication(processIdentifier: item.pid)
        let strategy = Self.resolveStrategy(
            activationPolicy: runningApp?.activationPolicy,
            button: button,
            preferAppActivationForRegularApps: preferAppActivationForRegularApps
        )

        switch strategy {
        case .activateApp:
            // Regular windowed app: bring directly to front (reopening closed main windows) with zero menu bar expansion.
            activateApplication(runningApp: runningApp, bundleIdentifier: item.bundleIdentifier)
            return

        case .forwardMenuBarItem(let clickButton):
            await forwardToMenuBarItem(item, button: clickButton, runningApp: runningApp)
        }
    }

    private func forwardToMenuBarItem(
        _ item: MenuBarItemInfo,
        button: MenuBarClickButton,
        runningApp: NSRunningApplication?
    ) async {
        let needsTransientExpand = item.section != .visible && !menuBarManager.isHiddenExpanded
        if needsTransientExpand {
            menuBarManager.expandTemporarilyForForwarding(targetPID: item.pid)
            // Allow WindowServer one brief layout frame to reposition the status item on screen.
            try? await Task.sleep(nanoseconds: 90_000_000)
        }

        // Strategy 1: Direct Accessibility action (`AXShowMenu` for right-click; `AXPress` -> `AXShowMenu` for left-click).
        let preferredActions: [String] = button == .right
            ? [kAXShowMenuAction as String]
            : [kAXPressAction as String, kAXShowMenuAction as String]

        let isTrusted = AXIsProcessTrusted()
        if isTrusted, performAXAction(for: item, preferredActions: preferredActions) {
            menuBarManager.postponeAutoRehide()
            return
        }

        // Synthetic clicks are silently dropped by the system without Accessibility trust,
        // so go straight to the app-activation fallback instead of a no-op flash.
        guard isTrusted else {
            if needsTransientExpand {
                menuBarManager.collapseIfTransient()
            }
            activateApplication(runningApp: runningApp, bundleIdentifier: item.bundleIdentifier)
            return
        }

        // Strategy 2: Re-scan live screen coordinates off-main and synthesize a left/right click, restoring cursor.
        let refreshed = await scanner.scanAsync(
            hiddenSeparatorX: menuBarManager.hiddenSeparatorX,
            excludingWindowIDs: menuBarManager.ownedWindowIDs
        )
        let refreshedItem = refreshed.first(where: { candidate in
            if candidate.windowID != 0 && candidate.windowID == item.windowID {
                return true
            }
            if candidate.pid == item.pid && !item.title.isEmpty && candidate.title == item.title {
                return true
            }
            if let bid = item.bundleIdentifier, !bid.isEmpty,
               candidate.bundleIdentifier == bid, candidate.pid == item.pid {
                return true
            }
            return candidate.pid == item.pid && candidate.title == item.title
        })
        let targetFrame: CGRect = refreshedItem?.frame ?? item.frame

        if targetFrame.width > 0 && Self.isOnAnyDisplay(CGPoint(x: targetFrame.midX, y: targetFrame.midY)) {
            postSyntheticClick(at: CGPoint(x: targetFrame.midX, y: targetFrame.midY), button: button)
            menuBarManager.postponeAutoRehide()
            return
        }

        // Strategy 3: Fallback — collapse transient expansion and activate the owning app.
        if needsTransientExpand {
            menuBarManager.collapseIfTransient()
        }
        activateApplication(runningApp: runningApp, bundleIdentifier: item.bundleIdentifier)
    }

    /// True when a CoreGraphics global point lies on a connected display (displays left of / above
    /// the primary display have negative coordinates, so `minX >= 0` is not a valid check).
    private static func isOnAnyDisplay(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return point.x >= 0 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return point.x >= 0 }
        return displays.prefix(Int(count)).contains { CGDisplayBounds($0).contains(point) }
    }

    private func activateApplication(runningApp: NSRunningApplication?, bundleIdentifier: String?) {
        if let bundleURL = runningApp?.bundleURL
            ?? bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
            return
        }
        runningApp?.activate(options: [.activateAllWindows])
    }

    private func performAXAction(for item: MenuBarItemInfo, preferredActions: [String]) -> Bool {
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.15)

        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extrasRef else {
            return false
        }

        let extrasBar = extrasRef as! AXUIElement
        AXUIElementSetMessagingTimeout(extrasBar, 0.15)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else {
            return false
        }

        let target = matchAXChild(in: children, for: item)
        AXUIElementSetMessagingTimeout(target, 0.15)

        // Inspect supported actions first so we don't fire unsupported actions blindly.
        var actionsRef: CFArray?
        let supportedActions: Set<String>
        if AXUIElementCopyActionNames(target, &actionsRef) == .success,
           let names = actionsRef as? [String] {
            supportedActions = Set(names)
        } else {
            supportedActions = []
        }

        for action in preferredActions {
            if !supportedActions.isEmpty && !supportedActions.contains(action) {
                continue
            }
            switch AXUIElementPerformAction(target, action as CFString) {
            case .success:
                return true
            case .cannotComplete:
                // AXPress on a status item often blocks until its menu stops tracking, so the short
                // messaging timeout fires while the menu is actually open. Treat it as dispatched;
                // following up with a synthetic click would close the menu again.
                return true
            default:
                continue
            }
        }
        return false
    }

    private func matchAXChild(in children: [AXUIElement], for item: MenuBarItemInfo) -> AXUIElement {
        // Bound every per-child IPC; the default ~6s timeout would freeze the main thread on a hung app.
        for child in children {
            AXUIElementSetMessagingTimeout(child, 0.15)
        }
        if !item.title.isEmpty {
            if let byTitle = children.first(where: { child in
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, title == item.title {
                    return true
                }
                var descRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descRef) == .success,
                   let desc = descRef as? String, desc == item.title {
                    return true
                }
                return false
            }) {
                return byTitle
            }
        }

        if children.count > 1 && item.frame.width > 0 {
            let targetMidX = item.frame.midX
            let ranked = children.compactMap { child -> (AXUIElement, CGFloat)? in
                var posRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef) == .success,
                      let posRef else {
                    return nil
                }
                var pt = CGPoint.zero
                guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pt) else { return nil }
                return (child, abs(pt.x - targetMidX))
            }
            if let closest = ranked.min(by: { $0.1 < $1.1 })?.0 {
                return closest
            }
        }

        return children[0]
    }

    private func postSyntheticClick(at point: CGPoint, button: MenuBarClickButton) {
        let originalLocation = CGEvent(source: nil)?.location

        let mouseButton: CGMouseButton = button == .right ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp

        guard let source = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: mouseButton),
              let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton),
              let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton) else {
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
