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
    var onHoverExpand: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Returns true only when the Notch panel is non-idle and actually needs pointer hit-test updates.
    var needsPointerTracking: (() -> Bool)?

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
        let shouldTrackNotch = needsPointerTracking?() ?? false
        let shouldTrackHover = settings.expandOnMenuBarHover
        // Fast-path exit when Notch is idle and menu-bar hover-expand is off: zero work per move.
        guard shouldTrackNotch || shouldTrackHover else { return }

        // Coalesce pointer updates to ~30Hz to keep idle CPU near 0%.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMoveDispatchTime >= 0.032 else { return }
        lastMoveDispatchTime = now

        if shouldTrackNotch {
            onMouseMoved?(location)
        }

        guard shouldTrackHover else {
            if hoverTimer != nil {
                hoverTimer?.invalidate()
                hoverTimer = nil
            }
            return
        }

        if isInRightMenuBarArea(location) {
            if hoverTimer == nil {
                let delay = max(0.15, settings.hoverDelaySeconds)
                hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.hoverTimer = nil
                        self?.onHoverExpand?()
                    }
                }
            }
        } else if hoverTimer != nil {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func isInMenuBar(_ point: CGPoint) -> Bool {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            let barHeight = max(screen.safeAreaInsets.top, 28)
            return point.y >= screen.frame.maxY - barHeight
        }
        return false
    }

    private func isInRightMenuBarArea(_ point: CGPoint) -> Bool {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            let barHeight = max(screen.safeAreaInsets.top, 28)
            let inHeight = point.y >= screen.frame.maxY - barHeight
            let inRightHalf = point.x >= screen.frame.midX + 60
            return inHeight && inRightHalf
        }
        return false
    }
}
