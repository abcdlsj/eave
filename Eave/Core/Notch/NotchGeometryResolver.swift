import AppKit
import Foundation

/// Resolves the primary notched display geometry, prioritizing the built-in notched MacBook screen.
@MainActor
enum NotchGeometryResolver {
    /// Returns the preferred screen for Notch UI:
    /// 1. Any display with a physical notch (`safeAreaInsets.top > 0`), preferring the primary screen (`frame.origin == .zero`).
    /// 2. Otherwise the primary screen (`NSScreen.screens.first`) or `NSScreen.main`.
    static func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let notchedScreens = screens.filter { $0.safeAreaInsets.top > 0 }
        if let primaryNotched = notchedScreens.first(where: { $0.frame.origin == .zero }) {
            return primaryNotched
        }
        if let firstNotched = notchedScreens.first {
            return firstNotched
        }
        return screens.first ?? NSScreen.main
    }

    static func currentGeometry() -> NotchGeometry {
        guard let screen = preferredScreen() else {
            return NotchGeometry.resolve(
                screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                safeAreaTop: 0,
                auxiliaryTopLeft: nil,
                auxiliaryTopRight: nil
            )
        }
        return geometry(for: screen)
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry.resolve(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
    }

    /// Heuristic check for whether a full-screen application currently hides the menu bar on the given screen.
    static func isFullScreenActive(on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        // In native full-screen space, visibleFrame extends all the way to the top edge (no menu bar reserved).
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        return topInset < 1.0 && screen.safeAreaInsets.top == 0
            || (screen.safeAreaInsets.top > 0 && topInset < screen.safeAreaInsets.top - 2.0)
    }
}
