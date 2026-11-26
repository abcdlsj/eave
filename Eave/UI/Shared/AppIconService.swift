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

    /// Fast icon-only lookup skipping dominant color extraction (ideal for 120fps Second-Row & Notch Bar tiles).
    func resolveIconOnly(for item: MenuBarItemInfo) -> (image: NSImage?, symbolName: String?) {
        let key = item.bundleIdentifier ?? "pid.\(item.pid).\(item.appName)"

        if let systemSymbol = Self.systemExtraSymbol(for: item) {
            return (nil, systemSymbol.symbol)
        }

        if let appIcon = highResAppIcon(bundleID: item.bundleIdentifier, pid: item.pid, cacheKey: key) {
            return (appIcon, nil)
        }

        return (nil, "app.fill")
    }

    /// Pre-warms cached rasterized icons off the main thread so startup and hover never pay
    /// synchronous 1024px `.icns` rasterization costs on `@MainActor`.
    func prewarm(items: [MenuBarItemInfo]) {
        prewarmAsync(items: items)
    }

    func prewarmAsync(items: [MenuBarItemInfo]) {
        var targets: [(cacheKey: String, filePath: String)] = []
        var seen = Set<String>()

        for item in items {
            let key = item.bundleIdentifier ?? "pid.\(item.pid).\(item.appName)"
            guard iconCache[key] == nil, seen.insert(key).inserted else { continue }
            guard Self.systemExtraSymbol(for: item) == nil else { continue }

            let path: String?
            if let bid = item.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                path = url.path
            } else if let app = NSRunningApplication(processIdentifier: item.pid),
                      let bundleURL = app.bundleURL {
                path = bundleURL.path
            } else {
                path = nil
            }

            if let path {
                targets.append((key, path))
            }
        }

        guard !targets.isEmpty else { return }
        let batch = targets
        Task.detached(priority: .utility) {
            var rendered: [(String, CGImage)] = []
            rendered.reserveCapacity(batch.count)
            for target in batch {
                let raw = NSWorkspace.shared.icon(forFile: target.filePath)
                if let cg = Self.rasterizeToCGImage(raw, pointSize: 36, scale: 2) {
                    rendered.append((target.cacheKey, cg))
                }
            }
            let completed = rendered
            await MainActor.run {
                let service = AppIconService.shared
                let size = NSSize(width: 36, height: 36)
                for (key, cg) in completed where service.iconCache[key] == nil {
                    service.iconCache[key] = NSImage(cgImage: cg, size: size)
                }
            }
        }
    }

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

    /// Resolves a Notch wing icon with strict priority:
    /// 1. Local image file path (`iconPath`)
    /// 2. Explicit SF Symbol (`symbolName`)
    /// 3. Installed macOS app icon (`bundleIdentifier`)
    /// 4. Neutral fallback SF Symbol
    func resolveNotchIcon(
        iconPath: String?,
        symbolName: String?,
        bundleIdentifier: String?,
        accentHex: String?
    ) -> ResolvedIcon {
        let resolvedAccent = Color(eaveHex: accentHex)

        if let rawPath = iconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty,
           let customImage = localFileIcon(at: rawPath) {
            return ResolvedIcon(
                image: customImage,
                symbolName: nil,
                accentColor: resolvedAccent,
                isTemplate: false
            )
        }

        if let rawSymbol = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawSymbol.isEmpty,
           NSImage(systemSymbolName: rawSymbol, accessibilityDescription: nil) != nil {
            return ResolvedIcon(
                image: nil,
                symbolName: rawSymbol,
                accentColor: resolvedAccent,
                isTemplate: true
            )
        }

        if let bundleID = bundleIdentifier,
           let icon = highResAppIcon(bundleID: bundleID, pid: nil, cacheKey: bundleID) {
            let color = accentHex != nil
                ? resolvedAccent
                : dominantColor(for: icon, cacheKey: bundleID)
            return ResolvedIcon(image: icon, symbolName: nil, accentColor: color, isTemplate: false)
        }

        return ResolvedIcon(
            image: nil,
            symbolName: "bell.fill",
            accentColor: resolvedAccent,
            isTemplate: true
        )
    }

    /// Resolves icon + ambient glow for a bundle identifier (used in Settings & watched app rows).
    func resolve(bundleIdentifier: String?, fallbackSymbol: String?, fallbackAccentHex: String?) -> ResolvedIcon {
        resolveNotchIcon(
            iconPath: nil,
            symbolName: bundleIdentifier == nil ? fallbackSymbol : nil,
            bundleIdentifier: bundleIdentifier,
            accentHex: fallbackAccentHex
        )
    }

    // MARK: - High-Res Icon Loading

    private static let maxLocalIconBytes = 8 * 1024 * 1024

    private func localFileIcon(at rawPath: String) -> NSImage? {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expanded).standardizedFileURL
        // Only plain, reasonably sized files: a device node (/dev/zero), FIFO, or huge image would
        // block the main thread while SwiftUI renders the notch.
        guard fileURL.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > 0, size <= Self.maxLocalIconBytes else {
            return nil
        }

        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let cacheKey = "file.\(fileURL.path).\(Int(mtime))"
        if let cached = iconCache[cacheKey] {
            return cached
        }

        guard let loaded = NSImage(contentsOfFile: fileURL.path), loaded.isValid else {
            return nil
        }
        let rasterized = Self.rasterize(loaded, pointSize: 36, scale: 2)
        // Scripts often generate a fresh temp icon per signal; keep file-backed entries bounded.
        let fileKeys = iconCache.keys.filter { $0.hasPrefix("file.") }
        if fileKeys.count >= 64 {
            for key in fileKeys { iconCache[key] = nil }
        }
        iconCache[cacheKey] = rasterized
        return rasterized
    }

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
        // Pre-rasterize once into a crisp 36pt@2x (72px) bitmap so ScrollView and hover never pay
        // runtime Lanczos downsampling costs on 1024px .icns representations.
        let rasterized = Self.rasterize(icon, pointSize: 36, scale: 2)
        iconCache[cacheKey] = rasterized
        return rasterized
    }

    private nonisolated static func rasterizeToCGImage(_ image: NSImage, pointSize: CGFloat, scale: CGFloat) -> CGImage? {
        let px = Int(pointSize * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            image.draw(
                in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func rasterize(_ image: NSImage, pointSize: CGFloat, scale: CGFloat) -> NSImage {
        guard let cg = rasterizeToCGImage(image, pointSize: pointSize, scale: scale) else {
            return image
        }
        return NSImage(cgImage: cg, size: NSSize(width: pointSize, height: pointSize))
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
