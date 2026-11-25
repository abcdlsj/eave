import AppKit
import Observation
import SwiftUI

/// Borderless, non-activating floating panel anchored seamlessly over the primary MacBook notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Float above the menu bar / status window layer without interrupting active apps.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }
}

/// Manages the lifecycle, screen geometry, hit-test pass-through, and SwiftUI hosting of the Notch panel.
@MainActor
final class NotchPanelController {
    private static let canvasWidth: CGFloat = 600
    private static let canvasHeight: CGFloat = 240

    private let stateMachine: NotchStateMachine
    private let panel: NotchPanel
    private var screenObserver: Any?
    private var spaceObserver: Any?

    private(set) var geometry: NotchGeometry
    private(set) var isFullScreenSuppressed: Bool = false

    var onGeometryChanged: ((NotchGeometry) -> Void)?

    init<Content: View>(stateMachine: NotchStateMachine, @ViewBuilder content: () -> Content) {
        self.stateMachine = stateMachine
        self.geometry = NotchGeometryResolver.currentGeometry()

        let frame = Self.panelFrame(for: geometry)
        self.panel = NotchPanel(contentRect: frame)

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        observeDisplayAndSpaceChanges()
        panel.orderFrontRegardless()
        updateMouseInteractivity()
    }

    func tearDown() {
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        if let obs = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceObserver = nil
        }
        panel.orderOut(nil)
    }

    func refreshGeometry() {
        let updated = NotchGeometryResolver.currentGeometry()
        geometry = updated
        let frame = Self.panelFrame(for: updated)
        panel.setFrame(frame, display: true)
        isFullScreenSuppressed = NotchGeometryResolver.isFullScreenActive(on: NotchGeometryResolver.preferredScreen())
        onGeometryChanged?(updated)
        updateMouseInteractivity()
    }

    /// Updates pass-through hit-testing so the Notch panel never blocks menu bar clicks when idle
    /// or when the pointer is outside the active rendered surface.
    func handleGlobalPointerMove(to point: CGPoint) {
        let activeRect = activeHitRect()
        let inside = activeRect.contains(point)

        let shouldIgnore: Bool
        switch stateMachine.state {
        case .idle:
            shouldIgnore = true
        case .ambient:
            shouldIgnore = !inside
        case .peek, .bar:
            shouldIgnore = !inside
            if inside != stateMachine.isHovering {
                stateMachine.setHovering(inside)
            }
        }

        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    func updateMouseInteractivity() {
        let point = NSEvent.mouseLocation
        handleGlobalPointerMove(to: point)
    }

    func isPointInsideActiveSurface(_ point: CGPoint) -> Bool {
        activeHitRect().contains(point)
    }

    // MARK: - Frame Calculations

    private static func panelFrame(for geometry: NotchGeometry) -> NSRect {
        let topY = geometry.isPhysicalNotch
            ? geometry.screenFrame.maxY
            : geometry.notchRect.maxY + 2
        return NSRect(
            x: geometry.notchRect.midX - canvasWidth / 2,
            y: topY - canvasHeight,
            width: canvasWidth,
            height: canvasHeight
        )
    }

    /// Approximate screen-space bounding box of the currently visible Notch surface.
    private func activeHitRect() -> CGRect {
        let topY = geometry.isPhysicalNotch ? geometry.screenFrame.maxY : geometry.notchRect.maxY
        let centerX = geometry.notchRect.midX
        let baseW = geometry.notchRect.width
        let baseH = geometry.notchRect.height

        switch stateMachine.state {
        case .idle:
            return .zero
        case .ambient:
            let w = baseW + 58
            let h = baseH + 2
            return CGRect(x: centerX - w / 2, y: topY - h, width: w, height: h)
        case .peek(_, let expanded):
            if expanded {
                let w: CGFloat = max(baseW + 150, 336)
                let h: CGFloat = baseH + 64
                return CGRect(x: centerX - w / 2, y: topY - h, width: w, height: h)
            } else {
                let w: CGFloat = baseW + 104
                let h: CGFloat = baseH + 4
                return CGRect(x: centerX - w / 2, y: topY - h, width: w, height: h)
            }
        case .bar:
            let w: CGFloat = 520
            let h: CGFloat = baseH + 116
            return CGRect(x: centerX - w / 2, y: topY - h, width: w, height: h)
        }
    }

    private func observeDisplayAndSpaceChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGeometry()
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGeometry()
            }
        }
    }
}
