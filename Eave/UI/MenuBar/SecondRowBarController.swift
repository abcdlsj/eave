import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Borderless, non-activating floating panel hosting Eave's Second-Row Menu Bar directly below the system menu bar.
/// Uses native WindowServer shadow (`hasShadow = true`) and hardware `alphaValue` fade for 120fps ProMotion smoothness.
final class SecondRowBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// When true (single-row horizontal layout), plain vertical mouse-wheel scrolling is remapped
    /// to horizontal scrolling so overflowing icons are reachable without Shift or a trackpad.
    var mapsVerticalScrollToHorizontal = false

    override func sendEvent(_ event: NSEvent) {
        if mapsVerticalScrollToHorizontal,
           event.type == .scrollWheel,
           abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
           let mapped = Self.horizontalScrollEvent(from: event) {
            super.sendEvent(mapped)
            return
        }
        super.sendEvent(event)
    }

    private static func horizontalScrollEvent(from event: NSEvent) -> NSEvent? {
        guard let cgEvent = event.cgEvent?.copy() else { return nil }
        let intFields: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)
        ]
        for (vertical, horizontal) in intFields {
            cgEvent.setIntegerValueField(horizontal, value: cgEvent.getIntegerValueField(vertical))
            cgEvent.setIntegerValueField(vertical, value: 0)
        }
        let fixed = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: cgEvent)
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}

/// Manages lifecycle, screen-clamped positioning, hover-bridge hysteresis, and zero-jank dismissal
/// for Eave's floating Second-Row Bar.
@MainActor
@Observable
final class SecondRowBarController {
    private static let dismissGraceSeconds: TimeInterval = 0.28
    private static let fadeInSeconds: TimeInterval = 0.14
    private static let fadeOutSeconds: TimeInterval = 0.22
    /// Pointer sampling interval while the card is visible. The global mouse-moved monitor is
    /// coalesced to ~30Hz and drops trailing events, and never fires while the pointer is over
    /// Eave's own windows, so a quick flick out of the card could leave it open indefinitely.
    private static let pointerPollSeconds: TimeInterval = 1.0 / 15.0

    private var panel: SecondRowBarPanel?
    private var dismissTimer: Timer?
    private var pointerPollTimer: Timer?
    private var escapeKeyMonitor: Any?
    private var localEscapeKeyMonitor: Any?
    private var appSwitchObserver: Any?
    private var presentationGeneration: UInt64 = 0
    private var lastAnchorFrame: CGRect?
    private(set) var isPinnedForPreview: Bool = false

    private(set) var appearanceMode: AppAppearanceMode = .system
    private(set) var items: [MenuBarItemInfo] = []
    private(set) var activeBadges: [String: String] = [:]
    private(set) var itemsPerRow: Int = EaveSettings.defaultSecondRowItemsPerRow
    private(set) var layoutMode: SecondRowLayoutMode = .horizontalScroll
    private(set) var maxContentWidth: CGFloat = SecondRowLayoutMetrics.defaultMaxContentWidth
    private(set) var isScanning: Bool = false
    private(set) var needsAccessibilityPermission: Bool = false
    private(set) var isVisible: Bool = false

    var onSelectItem: ((MenuBarItemInfo, MenuBarClickButton) -> Void)?
    var onRequestPermissions: (() -> Void)?
    /// Expands the hidden section so the • divider is visible for ⌘-dragging. The empty state
    /// shows a "Show Divider" button only when this is wired.
    var onRequestShowDivider: (() -> Void)?
    var shouldDismissOnAppSwitch: (() -> Bool)?

    init() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible, !self.isPinnedForPreview else { return }
                if self.shouldDismissOnAppSwitch?() ?? true {
                    self.hide()
                }
            }
        }
    }

    func applyAppearance(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        panel?.appearance = mode.nsAppearance
    }

    func tearDown() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        stopPointerPolling()
        removeEscapeMonitor()
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }

    /// Exact screen-space frame of the floating second-row card.
    var cardScreenFrame: CGRect {
        guard let frame = panel?.frame, isVisible else { return .zero }
        return frame
    }

    func isPointInsideCard(_ point: CGPoint) -> Bool {
        guard isVisible else { return false }
        return cardScreenFrame.contains(point)
    }

    func show(
        anchorFrame: CGRect?,
        items: [MenuBarItemInfo],
        activeBadges: [String: String],
        itemsPerRow: Int,
        layoutMode: SecondRowLayoutMode,
        isScanning: Bool,
        needsAccessibilityPermission: Bool = false,
        pinnedForPreview: Bool = false
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        presentationGeneration &+= 1

        self.lastAnchorFrame = anchorFrame
        self.items = items
        self.activeBadges = activeBadges
        self.itemsPerRow = EaveSettings.clampedItemsPerRow(itemsPerRow)
        self.layoutMode = layoutMode
        self.isScanning = isScanning
        self.needsAccessibilityPermission = needsAccessibilityPermission
        self.isPinnedForPreview = pinnedForPreview

        let screen = resolveScreen(for: anchorFrame)
        self.maxContentWidth = resolvedMaxContentWidth(for: screen)

        let targetFrame = computePanelFrame(anchorFrame: anchorFrame, screen: screen)
        let hostPanel = ensurePanel(initialFrame: targetFrame)
        hostPanel.mapsVerticalScrollToHorizontal = layoutMode == .horizontalScroll
        if hostPanel.frame != targetFrame {
            hostPanel.setFrame(targetFrame, display: false)
        }

        let wasVisible = isVisible
        isVisible = true
        installEscapeMonitorIfNeeded()
        startPointerPolling()

        if !wasVisible {
            // Resume from the current alpha so re-showing mid fade-out doesn't flash.
            if !hostPanel.isVisible { hostPanel.alphaValue = 0 }
            hostPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeInSeconds
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hostPanel.animator().alphaValue = 1
            }
        } else {
            hostPanel.alphaValue = 1
            hostPanel.orderFrontRegardless()
        }
    }

    func updateContent(
        items: [MenuBarItemInfo],
        activeBadges: [String: String],
        itemsPerRow: Int,
        layoutMode: SecondRowLayoutMode,
        isScanning: Bool,
        needsAccessibilityPermission: Bool = false,
        anchorFrame: CGRect? = nil
    ) {
        self.items = items
        self.activeBadges = activeBadges
        self.itemsPerRow = EaveSettings.clampedItemsPerRow(itemsPerRow)
        self.layoutMode = layoutMode
        self.isScanning = isScanning
        self.needsAccessibilityPermission = needsAccessibilityPermission
        if let anchorFrame {
            self.lastAnchorFrame = anchorFrame
        }

        panel?.mapsVerticalScrollToHorizontal = layoutMode == .horizontalScroll
        guard isVisible, let panel else { return }
        let screen = resolveScreen(for: self.lastAnchorFrame)
        self.maxContentWidth = resolvedMaxContentWidth(for: screen)
        let updatedFrame = computePanelFrame(anchorFrame: self.lastAnchorFrame, screen: screen)
        if panel.frame != updatedFrame {
            panel.setFrame(updatedFrame, display: false)
        }
    }

    func handleGlobalPointerMove(to point: CGPoint, anchorFrame: CGRect?) {
        guard isVisible else { return }
        let anchor = anchorFrame ?? lastAnchorFrame
        if let anchorFrame {
            lastAnchorFrame = anchorFrame
        }

        let insideSafeZone = SecondRowLayoutMetrics.isPointInHoverSafeZone(
            point,
            anchorFrame: anchor,
            cardScreenFrame: cardScreenFrame
        )

        if insideSafeZone {
            if isPinnedForPreview && cardScreenFrame.contains(point) {
                isPinnedForPreview = false
            }
            dismissTimer?.invalidate()
            dismissTimer = nil
        } else if !isPinnedForPreview && dismissTimer == nil {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.dismissGraceSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isVisible else { return }
                    self.dismissTimer = nil
                    let currentMouse = NSEvent.mouseLocation
                    let stillSafe = SecondRowLayoutMetrics.isPointInHoverSafeZone(
                        currentMouse,
                        anchorFrame: self.lastAnchorFrame,
                        cardScreenFrame: self.cardScreenFrame
                    )
                    if !stillSafe {
                        self.hide()
                    }
                }
            }
        }
    }

    func selectItem(_ item: MenuBarItemInfo, button: MenuBarClickButton = .left) {
        hide()
        onSelectItem?(item, button)
    }

    func hide() {
        guard isVisible else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil
        stopPointerPolling()
        removeEscapeMonitor()
        isPinnedForPreview = false

        let generation = presentationGeneration &+ 1
        presentationGeneration = generation
        isVisible = false

        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOutSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() during the fade bumps the generation; keep the panel on screen then.
                guard let self, self.presentationGeneration == generation else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    // MARK: - Private

    private func ensurePanel(initialFrame: CGRect) -> SecondRowBarPanel {
        if let panel { return panel }
        let created = SecondRowBarPanel(contentRect: initialFrame)
        created.appearance = appearanceMode.nsAppearance
        let hosting = NSHostingView(rootView: SecondRowBarView(controller: self))
        hosting.frame = NSRect(origin: .zero, size: initialFrame.size)
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        panel = created
        return created
    }

    private func resolvedMaxContentWidth(for screen: NSScreen?) -> CGFloat {
        let visibleWidth = screen?.visibleFrame.width ?? 1440
        return min(max(visibleWidth - 48, 320), SecondRowLayoutMetrics.defaultMaxContentWidth)
    }

    private func computePanelFrame(anchorFrame: CGRect?, screen: NSScreen?) -> CGRect {
        let metrics = SecondRowLayoutMetrics.resolve(
            itemCount: items.count,
            itemsPerRow: itemsPerRow,
            layoutMode: layoutMode,
            maxContentWidth: maxContentWidth
        )
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        let menuBarHeight: CGFloat
        if let screen {
            let safeTop = screen.safeAreaInsets.top
            let visibleTopInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            menuBarHeight = max(safeTop, visibleTopInset, 26)
        } else {
            menuBarHeight = 28
        }

        return SecondRowLayoutMetrics.panelFrame(
            contentSize: CGSize(width: metrics.contentWidth, height: metrics.contentHeight),
            anchorFrame: anchorFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            menuBarHeight: menuBarHeight
        )
    }

    private func resolveScreen(for anchorFrame: CGRect?) -> NSScreen? {
        if let anchor = anchorFrame {
            let center = CGPoint(x: anchor.midX, y: anchor.midY)
            if let matched = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                return matched
            }
            if let matched = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
                return matched
            }
        }
        return NotchGeometryResolver.preferredScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func startPointerPolling() {
        guard pointerPollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pointerPollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.handleGlobalPointerMove(to: NSEvent.mouseLocation, anchorFrame: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerPollTimer = timer
    }

    private func stopPointerPolling() {
        pointerPollTimer?.invalidate()
        pointerPollTimer = nil
    }

    private func installEscapeMonitorIfNeeded() {
        // Global monitor: Escape while another app is frontmost (requires Accessibility).
        if escapeKeyMonitor == nil {
            escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    MainActor.assumeIsolated {
                        self?.hide()
                    }
                }
            }
        }
        // Local monitor: Escape while one of Eave's own windows is key (e.g. Settings Preview),
        // which the global monitor never sees.
        if localEscapeKeyMonitor == nil {
            localEscapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event } // Escape
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.isVisible else { return false }
                    self.hide()
                    return true
                }
                return handled ? nil : event
            }
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        if let monitor = localEscapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeKeyMonitor = nil
        }
    }
}
