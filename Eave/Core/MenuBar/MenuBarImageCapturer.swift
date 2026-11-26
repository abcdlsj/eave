import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// On-demand single-frame icon capturer using ScreenCaptureKit (`SCScreenshotManager`).
/// Never opens a continuous SCStream so macOS never displays a persistent recording dot.
/// Gracefully falls back to the app's native icon when Screen Recording permission is absent.
@MainActor
final class MenuBarImageCapturer {
    private var iconCache: [String: NSImage] = [:]

    func captureItems(_ items: [MenuBarItemInfo], allowLiveCapture: Bool) async -> [CapturedMenuBarItem] {
        let canCaptureLive = allowLiveCapture && CGPreflightScreenCaptureAccess()

        if !canCaptureLive {
            // Views resolve cached high-DPI native App Icons via AppIconService; skip per-item NSImage copies here.
            return items.map { item in
                CapturedMenuBarItem(
                    info: item,
                    image: nil,
                    isLiveCapture: false
                )
            }
        }

        // Fetch shareable windows once per batch rather than per icon.
        let scWindowsByID: [CGWindowID: SCWindow]
        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            scWindowsByID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        } else {
            scWindowsByID = [:]
        }

        var results: [CapturedMenuBarItem] = []
        results.reserveCapacity(items.count)

        for item in items {
            if item.windowID > 0, let scWindow = scWindowsByID[item.windowID],
               let captured = await captureSingleWindow(scWindow) {
                iconCache[item.id] = captured
                results.append(CapturedMenuBarItem(info: item, image: captured, isLiveCapture: true))
            } else if let cached = iconCache[item.id] {
                results.append(CapturedMenuBarItem(info: item, image: cached, isLiveCapture: true))
            } else {
                results.append(CapturedMenuBarItem(info: item, image: fallbackAppIcon(for: item), isLiveCapture: false))
            }
        }

        return results
    }

    func clearCache() {
        iconCache.removeAll()
    }

    private func captureSingleWindow(_ window: SCWindow) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.capturesAudio = false

        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) else {
            return nil
        }

        let size = NSSize(width: window.frame.width, height: window.frame.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    private func fallbackAppIcon(for item: MenuBarItemInfo) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: item.pid), let icon = app.icon {
            let copy = icon.copy() as? NSImage ?? icon
            copy.size = NSSize(width: 22, height: 22)
            return copy
        }
        if let bundleID = item.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 22, height: 22)
            return icon
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: item.appName)
    }
}
