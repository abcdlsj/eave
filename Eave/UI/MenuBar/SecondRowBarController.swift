import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Borderless, non-activating floating panel hosting Eave's Second-Row Menu Bar directly below the system menu bar.
/// Uses native WindowServer shadow (`hasShadow = true`) and hardware `alphaValue` fade for 120fps ProMotion smoothness.
final class SecondRowBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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

    private var panel: SecondRowBarPanel?
    private var dismissTimer: Timer?
    private var hideOrderOutTask: Task<Void, Never>?
    private var escapeKeyMonitor: Any?
    private var appSwitchObserver: Any?
    private var presentationGeneration: UInt64 = 0
    private var lastAnchorFrame: CGRect?
    private var isPinnedForPreview: Bool = false
    private var preferredAppearance: NSAppearance?

    private(set) var items: [CapturedMenuBarItem] = []
    private(set) var activeBadges: [String: String] = [:]
    private(set) var itemsPerRow: Int = EaveSettings.defaultSecondRowItemsPerRow
    private(set) var layoutMode: SecondRowLayoutMode = .horizontalScroll
    private(set) var maxContentWidth: CGFloat = SecondRowLayoutMetrics.defaultMaxContentWidth
    private(set) var isScanning: Bool = false
    private(set) var needsAccessibilityPermission: Bool = false
    private(set) var isVisible: Bool = false

    var onSelectItem: ((MenuBarItemInfo) -> Void)?
    var onRequestPermissions: (() -> Void)?
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

    func applyAppearance(_ appearance: NSAppearance?) {
        preferredAppearance = appearance
        panel?.appearance = appearance
    }

    func tearDown() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        hideOrderOutTask?.cancel()
        hideOrderOutTask = nil
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
        items: [CapturedMenuBarItem],
        activeBadges: [String: String],
        itemsPerRow: Int,
        layoutMode: SecondRowLayoutMode,
        isScanning: Bool,
        needsAccessibilityPermission: Bool = false,
        pinnedForPreview: Bool = false
    ) {
        hideOrderOutTask?.cancel()
        hideOrderOutTask = nil
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
        if hostPanel.frame != targetFrame {
            hostPanel.setFrame(targetFrame, display: false)
        }

        let wasVisible = isVisible
        isVisible = true
        installEscapeMonitorIfNeeded()

        if !wasVisible {
            hostPanel.alphaValue = 0
            hostPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hostPanel.animator().alphaValue = 1
            }
        } else {
            hostPanel.alphaValue = 1
            hostPanel.orderFrontRegardless()
        }
    }

    func updateContent(
        items: [CapturedMenuBarItem],
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

    func selectItem(_ item: MenuBarItemInfo) {
        hide()
        onSelectItem?(item)
    }

    func hide() {
        guard isVisible else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeEscapeMonitor()
        isPinnedForPreview = false

        let generation = presentationGeneration &+ 1
        presentationGeneration = generation
        isVisible = false

        if let panel {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.11
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
        }

        hideOrderOutTask?.cancel()
        hideOrderOutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled, self.presentationGeneration == generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    // MARK: - Private

    private func ensurePanel(initialFrame: CGRect) -> SecondRowBarPanel {
        if let panel { return panel }
        let created = SecondRowBarPanel(contentRect: initialFrame)
        created.appearance = preferredAppearance
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

    private func installEscapeMonitorIfNeeded() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                MainActor.assumeIsolated {
                    self?.hide()
                }
            }
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }
}
