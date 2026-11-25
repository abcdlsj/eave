import AppKit
import CoreGraphics
import SwiftUI

/// Provides crisp high-resolution macOS App Icons, tailored SF Symbols for system menu bar extras,
/// and cached dominant accent colors for subtle ambient icon lighting inside Notch surfaces.
@MainActor
final class AppIconService {
    static let shared = AppIconService()

    struct ResolvedIcon {
        let image: NSImage?
        let symbolName: String?
        let accentColor: Color
        let isTemplate: Bool
    }

    private var iconCache: [String: NSImage] = [:]
    private var colorCache: [String: Color] = [:]

    private init() {}

    /// Resolves the highest-quality visual icon and dominant glow color for a menu bar item.
    func resolve(for item: MenuBarItemInfo) -> ResolvedIcon {
        let key = item.bundleIdentifier ?? "pid.\(item.pid).\(item.appName)"

        // System Control Center / macOS built-in extras look much sharper as optical SF Symbols
        // than generic Control Center gear icons.
        if let systemSymbol = Self.systemExtraSymbol(for: item) {
            return ResolvedIcon(
                image: nil,
                symbolName: systemSymbol.symbol,
                accentColor: systemSymbol.color,
                isTemplate: true
            )
        }

        if let appIcon = highResAppIcon(bundleID: item.bundleIdentifier, pid: item.pid, cacheKey: key) {
            let glow = dominantColor(for: appIcon, cacheKey: key)
            return ResolvedIcon(image: appIcon, symbolName: nil, accentColor: glow, isTemplate: false)
        }

        return ResolvedIcon(
            image: nil,
            symbolName: "app.fill",
            accentColor: Color(red: 0.45, green: 0.65, blue: 1.0),
            isTemplate: true
        )
    }

    /// Resolves icon + ambient glow for a bundle identifier (used in Notch Peek & Ambient states).
    func resolve(bundleIdentifier: String?, fallbackSymbol: String?, fallbackAccentHex: String?) -> ResolvedIcon {
        if let bundleID = bundleIdentifier,
           let icon = highResAppIcon(bundleID: bundleID, pid: nil, cacheKey: bundleID) {
            let color = fallbackAccentHex != nil
                ? Color(eaveHex: fallbackAccentHex)
                : dominantColor(for: icon, cacheKey: bundleID)
            return ResolvedIcon(image: icon, symbolName: nil, accentColor: color, isTemplate: false)
        }

        return ResolvedIcon(
            image: nil,
            symbolName: fallbackSymbol ?? "bell.badge.fill",
            accentColor: Color(eaveHex: fallbackAccentHex),
            isTemplate: true
        )
    }

    // MARK: - High-Res Icon Loading

    private func highResAppIcon(bundleID: String?, pid: pid_t?, cacheKey: String) -> NSImage? {
        if let cached = iconCache[cacheKey] {
            return cached
        }

        var loaded: NSImage?
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            loaded = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            if let bundleURL = app.bundleURL {
                loaded = NSWorkspace.shared.icon(forFile: bundleURL.path)
            } else {
                loaded = app.icon
            }
        }

        guard let icon = loaded else { return nil }
        // Request crisp retina 128pt representation so downscaling to 32-44pt stays razor-sharp.
        let sized = icon.copy() as? NSImage ?? icon
        sized.size = NSSize(width: 128, height: 128)
        iconCache[cacheKey] = sized
        return sized
    }

    // MARK: - Fast Dominant Color Extraction

    private func dominantColor(for image: NSImage, cacheKey: String) -> Color {
        if let cached = colorCache[cacheKey] {
            return cached
        }

        let sampleSize = 12
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.medium.rawValue)]
        ) else {
            return Color.white.opacity(0.6)
        }

        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Color.white.opacity(0.6)
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var bestR: Double = 0.55
        var bestG: Double = 0.72
        var bestB: Double = 1.0
        var bestScore: Double = 0

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255.0
            guard a > 0.5 else { continue }
            let r = Double(pixels[i]) / 255.0 / a
            let g = Double(pixels[i + 1]) / 255.0 / a
            let b = Double(pixels[i + 2]) / 255.0 / a

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let brightness = maxC

            // Favor vibrant, readable hues over near-black or pure-white corners.
            let score = saturation * 1.6 + (brightness > 0.25 && brightness < 0.95 ? 0.4 : 0.05)
            if score > bestScore {
                bestScore = score
                bestR = min(max(r, 0), 1)
                bestG = min(max(g, 0), 1)
                bestB = min(max(b, 0), 1)
            }
        }

        // Lift dark accents slightly so they glow subtly against pure black obsidian.
        let lifted = Color(
            red: min(1.0, bestR * 0.85 + 0.15),
            green: min(1.0, bestG * 0.85 + 0.15),
            blue: min(1.0, bestB * 0.85 + 0.15)
        )
        colorCache[cacheKey] = lifted
        return lifted
    }

    // MARK: - System Menu Bar Extra Symbols

    private static func systemExtraSymbol(for item: MenuBarItemInfo) -> (symbol: String, color: Color)? {
        let bundle = (item.bundleIdentifier ?? "").lowercased()
        let text = item.searchableText.lowercased()

        let isSystem = bundle.hasPrefix("com.apple.controlcenter")
            || bundle.hasPrefix("com.apple.systemuiserver")
            || bundle.hasPrefix("com.apple.textinputmenuagent")
            || item.appName == "Control Center"

        guard isSystem else { return nil }

        if text.contains("wi-fi") || text.contains("wifi") {
            return ("wifi", Color(red: 0.25, green: 0.65, blue: 1.0))
        }
        if text.contains("bluetooth") {
            return ("wave.3.right.circle.fill", Color(red: 0.28, green: 0.60, blue: 1.0))
        }
        if text.contains("battery") || text.contains("power") {
            return ("battery.100percent", Color(red: 0.28, green: 0.84, blue: 0.48))
        }
        if text.contains("sound") || text.contains("volume") || text.contains("audio") {
            return ("speaker.wave.2.fill", Color(red: 0.95, green: 0.45, blue: 0.55))
        }
        if text.contains("focus") || text.contains("do not disturb") {
            return ("moon.fill", Color(red: 0.58, green: 0.46, blue: 1.0))
        }
        if text.contains("clock") || text.contains("time") {
            return ("clock.fill", Color.white.opacity(0.85))
        }
        if text.contains("airdrop") {
            return ("airplayaudio", Color(red: 0.25, green: 0.65, blue: 1.0))
        }
        if text.contains("screen") || text.contains("display") || text.contains("mirror") {
            return ("rectangle.on.rectangle", Color(red: 0.35, green: 0.72, blue: 1.0))
        }
        if text.contains("input") || text.contains("keyboard") || bundle.contains("textinput") {
            return ("keyboard", Color.white.opacity(0.82))
        }
        if text.contains("spotlight") {
            return ("magnifyingglass", Color.white.opacity(0.85))
        }
        return ("switch.2", Color.white.opacity(0.78))
    }
}
