import AppKit
import Foundation

/// Lightweight global event monitor for Eave hover-to-reveal and click-away rehide.
/// Designed for zero per-pixel Task allocations and negligible CPU overhead during normal mouse movement.
@MainActor
final class MenuBarEventMonitor {
    private let settings: EaveSettings
    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var hoverTimer: Timer?
    private var trailingMoveTimer: Timer?
    private var lastMoveDispatchTime: CFAbsoluteTime = 0

    var onHoverExpand: ((CGRect?) -> Void)?
    var onOutsideClick: (() -> Void)?
    /// Mouse-down inside the menu bar band of any display.
    var onMenuBarClick: ((CGPoint) -> Void)?
    /// Any mouse-up (inMenuBar, commandHeld) — lets the menu bar manager re-check layout after ⌘-drags.
    var onMouseUp: ((Bool, Bool) -> Void)?
    /// Pointer left the Eave icon (after having been over it).
    var onToggleHoverExit: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Returns true when any floating overlay (Notch or Second Row Bar) needs pointer tracking.
    var needsPointerTracking: (() -> Bool)?
    /// Screen-space frames of Eave's toggle button across ALL connected displays.
    var toggleItemFramesProvider: (() -> [CGRect])?
    /// Returns true if hover expansion should be temporarily suppressed (e.g. context menu or search open).
    var isHoverSuppressed: (() -> Bool)?

    private var isPointerOverEaveToggle: Bool = false
    private var hoveredToggleFrame: CGRect?
    /// After a click on the Eave icon, hover must not re-trigger until the pointer has left the icon;
    /// otherwise a click-to-collapse is immediately undone by the hover reveal.
    private var hoverRequiresExit: Bool = false

    init(settings: EaveSettings) {
        self.settings = settings
    }

    func start() {
        stop()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseDown(location: NSEvent.mouseLocation)
            }
        }

        // Dragged events matter too: while ⌘-dragging an icon, `.mouseMoved` is not delivered.
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseMoved(location: NSEvent.mouseLocation)
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            let commandHeld = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated {
                guard let self else { return }
                let loc = NSEvent.mouseLocation
                self.onMouseUp?(self.isInMenuBar(loc), commandHeld)
            }
        }
    }

    func stop() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m) }
        globalClickMonitor = nil
        globalMoveMonitor = nil
        globalMouseUpMonitor = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        trailingMoveTimer?.invalidate()
        trailingMoveTimer = nil
    }

    /// Cancels a pending hover reveal. With `requireExit`, hover stays disarmed until the pointer leaves the icon
    /// (used when the user clicks the icon, so the click result is not overridden by a hover a moment later).
    func cancelPendingHover(requireExit: Bool = false) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if requireExit {
            // Keep `isPointerOverEaveToggle` truthful so the exit is still detected and re-arms hover.
            hoverRequiresExit = true
        } else {
            isPointerOverEaveToggle = false
            hoveredToggleFrame = nil
        }
    }

    /// Invoked either by `StatusItemHoverView`'s native `NSTrackingArea` or by global pointer tracking
    /// when the cursor enters or leaves any display's Eave menu bar icon.
    func handleEaveToggleHover(isHovering: Bool, anchorFrame: CGRect? = nil) {
        guard settings.expandOnEaveHover else {
            cancelPendingHover()
            return
        }

        if isHovering {
            if let anchorFrame {
                hoveredToggleFrame = anchorFrame
            } else if hoveredToggleFrame == nil {
                hoveredToggleFrame = matchingToggleFrame(at: NSEvent.mouseLocation)
            }
            // Two sources report hover (the button's tracking area and the global monitor); a duplicate
            // "enter" must not restart anything, but it must still be able to start a timer that a
            // previous blocked attempt (e.g. ⌘ held, button down) never started.
            isPointerOverEaveToggle = true

            guard !hoverRequiresExit else { return }
            guard shouldAllowHoverTrigger() else { return }
            guard hoverTimer == nil else { return }

            let delay = max(0.05, min(settings.hoverDelaySeconds, 1.0))
            hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hoverTimer = nil
                    let loc = NSEvent.mouseLocation
                    guard self.settings.expandOnEaveHover,
                          self.isPointerOverEaveToggle,
                          !self.hoverRequiresExit,
                          self.shouldAllowHoverTrigger(),
                          let activeAnchor = self.matchingToggleFrame(at: loc) else {
                        return
                    }
                    self.hoveredToggleFrame = activeAnchor
                    self.onHoverExpand?(activeAnchor)
                }
            }
        } else {
            // The button's tracking area reports "exit" when the pointer slides into the small cushion around
            // the icon; that is still "over the icon" for hover purposes.
            if matchingToggleFrame(at: NSEvent.mouseLocation) != nil { return }
            let wasOver = isPointerOverEaveToggle
            isPointerOverEaveToggle = false
            hoverRequiresExit = false
            hoveredToggleFrame = nil
            hoverTimer?.invalidate()
            hoverTimer = nil
            if wasOver {
                onToggleHoverExit?()
            }
        }
    }

    private func handleMouseDown(location: CGPoint) {
        if isInMenuBar(location) {
            onMenuBarClick?(location)
            return
        }
        onOutsideClick?()
    }

    private func handleMouseMoved(location: CGPoint) {
        let shouldTrackOverlay = needsPointerTracking?() ?? false
        let shouldTrackHover = settings.expandOnEaveHover
        // Fast-path exit when overlays are idle and Eave hover-expand is off: zero work per move.
        guard shouldTrackOverlay || shouldTrackHover else {
            if hoverTimer != nil || isPointerOverEaveToggle { cancelPendingHover() }
            return
        }

        // Hover enter/exit is a few rect checks: evaluate it on EVERY event. Throttling it dropped the
        // final "left the icon" event when the pointer stopped right after leaving, leaving hover stuck.
        if shouldTrackHover {
            let matched = matchingToggleFrame(at: location)
            let hoveringToggle = matched != nil
            if hoveringToggle != isPointerOverEaveToggle {
                handleEaveToggleHover(isHovering: hoveringToggle, anchorFrame: matched)
            } else if let matched {
                hoveredToggleFrame = matched
            }
        }

        guard shouldTrackOverlay else { return }

        // Coalesce overlay updates to ~30Hz, but always deliver the last position (trailing edge) so the
        // overlays see where the pointer finally stopped.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMoveDispatchTime >= 0.032 {
            lastMoveDispatchTime = now
            trailingMoveTimer?.invalidate()
            trailingMoveTimer = nil
            onMouseMoved?(location)
        } else if trailingMoveTimer == nil {
            trailingMoveTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.trailingMoveTimer = nil
                    self.lastMoveDispatchTime = CFAbsoluteTimeGetCurrent()
                    if self.needsPointerTracking?() ?? false {
                        self.onMouseMoved?(NSEvent.mouseLocation)
                    }
                }
            }
        }
    }

    private func shouldAllowHoverTrigger() -> Bool {
        // Never interrupt ⌘-rearranging menu bar items, active mouse drags, or open menus/overlays.
        guard NSEvent.pressedMouseButtons == 0 else { return false }
        guard !NSEvent.modifierFlags.contains(.command) else { return false }
        guard !(isHoverSuppressed?() ?? false) else { return false }
        return true
    }

    private func matchingToggleFrame(at point: CGPoint) -> CGRect? {
        guard let frames = toggleItemFramesProvider?(), !frames.isEmpty else {
            return nil
        }
        // Small 3pt cushion absorbs sub-pixel edge jitter on Retina and external displays.
        return frames.first { frame in
            frame.width > 0 && frame.height > 0 && frame.insetBy(dx: -3, dy: -3).contains(point)
        }
    }

    private func isInMenuBar(_ point: CGPoint) -> Bool {
        MenuBarManager.isPointInMenuBar(point)
    }
}
