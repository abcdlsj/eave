import AppKit
import Foundation

/// Passive global event monitor for menu bar scroll gestures, hover-to-expand, and click-away rehide.
@MainActor
final class MenuBarEventMonitor {
    private let settings: EaveSettings
    private var globalScrollMonitor: Any?
    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    private var hoverTimer: Timer?
    private var lastScrollTriggerDate: Date = .distantPast

    var onScrollExpand: (() -> Void)?
    var onScrollCollapse: (() -> Void)?
    var onHoverExpand: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?

    init(settings: EaveSettings) {
        self.settings = settings
    }

    func start() {
        stop()

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let deltaY = event.scrollingDeltaY
            let deltaX = event.scrollingDeltaX
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleScroll(deltaX: deltaX, deltaY: deltaY, location: location)
            }
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleOutsideClick(location: location)
            }
        }

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleMouseMoved(location: location)
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
        let now = Date()
        guard now.timeIntervalSince(lastScrollTriggerDate) > 0.35 else { return }

        let magnitude = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        guard abs(magnitude) > 2.5 else { return }

        lastScrollTriggerDate = now
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
        onMouseMoved?(location)

        guard settings.expandOnMenuBarHover else {
            hoverTimer?.invalidate()
            hoverTimer = nil
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
        } else {
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
