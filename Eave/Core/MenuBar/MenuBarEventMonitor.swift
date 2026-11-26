import AppKit
import Foundation

/// Lightweight global event monitor for menu bar scroll gestures, hover-to-expand, and click-away rehide.
/// Designed for zero per-pixel Task allocations and negligible CPU overhead during normal mouse movement.
@MainActor
final class MenuBarEventMonitor {
    private let settings: EaveSettings
    private var globalScrollMonitor: Any?
    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    private var hoverTimer: Timer?
    private var lastScrollTriggerTime: CFAbsoluteTime = 0
    private var lastMoveDispatchTime: CFAbsoluteTime = 0

    var onScrollExpand: (() -> Void)?
    var onScrollCollapse: (() -> Void)?
    var onHoverExpand: ((CGRect?) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Returns true when any floating overlay (Notch or Second Row Bar) needs pointer tracking.
    var needsPointerTracking: (() -> Bool)?
    /// Screen-space frames of Eave's toggle button across ALL connected displays.
    var toggleItemFramesProvider: (() -> [CGRect])?
    /// Returns true if hover expansion should be temporarily suppressed (e.g. context menu or another panel open).
    var isHoverSuppressed: (() -> Bool)?

    private var isPointerOverEaveToggle: Bool = false
    private var hoveredToggleFrame: CGRect?

    init(settings: EaveSettings) {
        self.settings = settings
    }

    func start() {
        stop()

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, location: NSEvent.mouseLocation)
            }
        }

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
        if let m = globalScrollMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        globalScrollMonitor = nil
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

            guard shouldAllowHoverTrigger() else { return }
            guard hoverTimer == nil else { return }

            let delay = max(0.05, min(settings.hoverDelaySeconds, 1.0))
            hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hoverTimer = nil
                    let loc = NSEvent.mouseLocation
                    guard self.settings.expandOnEaveHover,
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
            hoveredToggleFrame = nil
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint) {
        guard settings.expandOnMenuBarScroll, isInMenuBar(location) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastScrollTriggerTime > 0.35 else { return }

        let magnitude = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        guard abs(magnitude) > 2.5 else { return }

        lastScrollTriggerTime = now
        if magnitude > 0 {
            onScrollExpand?()
        } else {
            onScrollCollapse?()
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
        for screen in NSScreen.screens where screen.frame.contains(point) {
            let barHeight = max(screen.safeAreaInsets.top, 28)
            return point.y >= screen.frame.maxY - barHeight
        }
        return false
    }
}
