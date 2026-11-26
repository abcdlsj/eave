import AppKit
import Foundation

/// Lightweight global event monitor for Eave hover-to-reveal and click-away rehide.
/// Designed for zero per-pixel Task allocations and negligible CPU overhead during normal mouse movement.
@MainActor
final class MenuBarEventMonitor {
    private let settings: EaveSettings
    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    private var hoverTimer: Timer?
    private var lastMoveDispatchTime: CFAbsoluteTime = 0

    var onHoverExpand: ((CGRect?) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Returns true when any floating overlay (Notch or Second Row Bar) needs pointer tracking.
    var needsPointerTracking: (() -> Bool)?
    /// Screen-space frames of Eave's toggle button across ALL connected displays.
    var toggleItemFramesProvider: (() -> [CGRect])?
    /// Returns true if hover expansion should be temporarily suppressed (e.g. context menu or search open).
    var isHoverSuppressed: (() -> Bool)?

    private var isPointerOverEaveToggle: Bool = false
    private var hoveredToggleFrame: CGRect?
    /// Set after an explicit click on the Eave icon so the pointer still resting on it
    /// cannot immediately re-trigger hover reveal (which used to undo the click).
    private(set) var isHoverSuppressedUntilExit: Bool = false

    init(settings: EaveSettings) {
        self.settings = settings
    }

    func start() {
        stop()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleOutsideClick(location: NSEvent.mouseLocation)
            }
        }

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseMoved(location: NSEvent.mouseLocation)
            }
        }
    }

    func stop() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        globalClickMonitor = nil
        globalMoveMonitor = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    func cancelPendingHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        isPointerOverEaveToggle = false
        hoveredToggleFrame = nil
    }

    /// Called when the user explicitly clicks the Eave icon. Cancels any pending hover reveal and keeps
    /// hover reveal disarmed until the pointer leaves the icon, so the click result stays stable.
    func suppressHoverUntilPointerExits() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        isHoverSuppressedUntilExit = true
        let loc = NSEvent.mouseLocation
        hoveredToggleFrame = matchingToggleFrame(at: loc)
        isPointerOverEaveToggle = hoveredToggleFrame != nil
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
            guard !isPointerOverEaveToggle else { return }
            isPointerOverEaveToggle = true

            guard !isHoverSuppressedUntilExit else { return }
            guard shouldAllowHoverTrigger() else { return }
            guard hoverTimer == nil else { return }

            let delay = max(0.05, min(settings.hoverDelaySeconds, 1.0))
            hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hoverTimer = nil
                    let loc = NSEvent.mouseLocation
                    guard self.settings.expandOnEaveHover,
                          !self.isHoverSuppressedUntilExit,
                          self.shouldAllowHoverTrigger(),
                          let activeAnchor = self.matchingToggleFrame(at: loc) else {
                        return
                    }
                    self.hoveredToggleFrame = activeAnchor
                    self.onHoverExpand?(activeAnchor)
                }
            }
        } else {
            isPointerOverEaveToggle = false
            isHoverSuppressedUntilExit = false
            hoveredToggleFrame = nil
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func handleOutsideClick(location: CGPoint) {
        guard !isInMenuBar(location) else { return }
        onOutsideClick?()
    }

    private func handleMouseMoved(location: CGPoint) {
        let shouldTrackOverlay = needsPointerTracking?() ?? false
        let shouldTrackHover = settings.expandOnEaveHover
        // Fast-path exit when overlays are idle and Eave hover-expand is off: zero work per move.
        guard shouldTrackOverlay || shouldTrackHover else { return }

        // Coalesce pointer updates to ~30Hz to keep idle CPU near 0%.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMoveDispatchTime >= 0.032 else { return }
        lastMoveDispatchTime = now

        if shouldTrackOverlay {
            onMouseMoved?(location)
        }

        if shouldTrackHover {
            let matched = matchingToggleFrame(at: location)
            let hoveringToggle = matched != nil
            if hoveringToggle != isPointerOverEaveToggle {
                handleEaveToggleHover(isHovering: hoveringToggle, anchorFrame: matched)
            } else if let matched {
                hoveredToggleFrame = matched
            } else if isHoverSuppressedUntilExit {
                // Safety net: the pointer is provably off every Eave icon, so re-arm hover.
                isHoverSuppressedUntilExit = false
            }
        } else if hoverTimer != nil {
            cancelPendingHover()
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
        // Extend 1pt upwards: `NSRect.contains` excludes `maxY`, so the topmost pixel row would
        // otherwise be treated as an outside click and collapse the menu bar.
        for screen in NSScreen.screens where screen.frame.insetBy(dx: 0, dy: -1).contains(point) {
            let barHeight = max(screen.safeAreaInsets.top, 28)
            return point.y >= screen.frame.maxY - barHeight
        }
        return false
    }
}
