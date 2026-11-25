#!/usr/bin/env swift

import AppKit
import Foundation

// Generates minimalist single-shape Eave icons for AppIcon.appiconset and MenuBarIcon.imageset.
// Design: a poised modernist architectural eave (cantilevered roof silhouette with subtle sori curvature),
// rendered as one clean continuous geometric mark.

let fileManager = FileManager.default
let rootDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let assetsDir = rootDir.appendingPathComponent("Eave/Resources/Assets.xcassets")
let appIconDir = assetsDir.appendingPathComponent("AppIcon.appiconset")
let menuBarDir = assetsDir.appendingPathComponent("MenuBarIcon.imageset")

try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: menuBarDir, withIntermediateDirectories: true)

/// Returns the canonical single-shape architectural Eave silhouette inside `rect`.
/// Design: crisp precision-milled modernist eave — poised pitched ridge, subtle concave sori sweep,
/// and taut cantilevered wingtips with architectural micro-chamfered corners.
func makeEaveGlyphPath(in rect: CGRect, opticalWeight: CGFloat = 1.0) -> CGPath {
    let w = rect.width
    let h = rect.height
    let ox = rect.minX
    let oy = rect.minY

    func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: ox + w * nx, y: oy + h * ny)
    }

    let t = opticalWeight
    let ridgeTopY: CGFloat = 0.655 + 0.015 * (t - 1.0)
    let ridgeBotY: CGFloat = ridgeTopY - 0.125 * t

    // Taut cantilevered eave wingtips with subtle upward architectural lift.
    let tipOuterTopY: CGFloat = 0.435 + 0.010 * (t - 1.0)
    let tipOuterBotY: CGFloat = tipOuterTopY - 0.072 * t
    let leftTipX: CGFloat = 0.065
    let rightTipX: CGFloat = 0.935
    let leftBotX: CGFloat = 0.105
    let rightBotX: CGFloat = 0.895

    let path = CGMutablePath()

    // Left outer architectural bevel tip (crisp cantilevered fascia edge).
    path.move(to: p(leftTipX, tipOuterTopY))

    // Left sweeping roof slope (subtle concave sori curve up to crisp ridge).
    path.addCurve(
        to: p(0.482, ridgeTopY - 0.008),
        control1: p(0.24, tipOuterTopY - 0.015),
        control2: p(0.37, ridgeTopY - 0.095)
    )

    // Crisp, taut architectural ridge apex (micro-radius for precision milled feel).
    path.addQuadCurve(
        to: p(0.518, ridgeTopY - 0.008),
        control: p(0.500, ridgeTopY + 0.006)
    )

    // Right sweeping roof slope mirrored cleanly to the right cantilevered tip.
    path.addCurve(
        to: p(rightTipX, tipOuterTopY),
        control1: p(0.63, ridgeTopY - 0.095),
        control2: p(0.76, tipOuterTopY - 0.015)
    )

    // Crisp angled fascia cut on the right eave overhang (tucking cleanly inward underneath).
    path.addQuadCurve(
        to: p(rightBotX, tipOuterBotY),
        control: p(rightTipX - 0.008, tipOuterBotY + 0.006)
    )

    // Right sheltered underside (soffit) sweeping smoothly to the centered inner ridge.
    path.addCurve(
        to: p(0.516, ridgeBotY - 0.006),
        control1: p(0.74, tipOuterBotY - 0.008),
        control2: p(0.62, ridgeBotY - 0.088)
    )

    // Crisp centered inner ridge arch.
    path.addQuadCurve(
        to: p(0.484, ridgeBotY - 0.006),
        control: p(0.500, ridgeBotY + 0.008)
    )

    // Left sheltered underside sweeping symmetrically to the left overhang tuck.
    path.addCurve(
        to: p(leftBotX, tipOuterBotY),
        control1: p(0.38, ridgeBotY - 0.088),
        control2: p(0.26, tipOuterBotY - 0.008)
    )

    // Crisp angled fascia cut closing back to the left outer eave tip.
    path.addQuadCurve(
        to: p(leftTipX, tipOuterTopY),
        control: p(leftTipX + 0.008, tipOuterBotY + 0.006)
    )

    path.closeSubpath()
    return path
}

func writePNG(width: Int, height: Int, to url: URL, draw: (CGContext, CGRect) -> Void) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create NSBitmapImageRep")
    }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create NSGraphicsContext")
    }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    draw(ctx, CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    try pngData.write(to: url)
}

func renderAppIcon(pixelSize: Int, to url: URL) throws {
    try writePNG(width: pixelSize, height: pixelSize, to: url) { ctx, bounds in
        let s = bounds.width
        let inset = s * 0.095
        let cardRect = bounds.insetBy(dx: inset, dy: inset)
        let cornerRadius = cardRect.width * 0.225
        let space = CGColorSpaceCreateDeviceRGB()

        let tilePath = CGPath(
            roundedRect: cardRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Subtle outer drop shadow for the squircle tile.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.012),
            blur: s * 0.028,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
        )
        ctx.addPath(tilePath)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.085, blue: 0.098, alpha: 1.0))
        ctx.fillPath()
        ctx.restoreGState()

        // Rich anodized obsidian tile with subtle top architectural sheen.
        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()

        let bgColors = [
            CGColor(red: 0.165, green: 0.175, blue: 0.200, alpha: 1.0),
            CGColor(red: 0.095, green: 0.100, blue: 0.116, alpha: 1.0),
            CGColor(red: 0.055, green: 0.058, blue: 0.070, alpha: 1.0)
        ] as CFArray
        if let bgGradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
            ctx.drawLinearGradient(
                bgGradient,
                start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
                end: CGPoint(x: cardRect.midX, y: cardRect.minY),
                options: []
            )
        }

        // Soft overhead radial atmosphere behind the eave ridge.
        let glowColors = [
            CGColor(red: 0.60, green: 0.72, blue: 0.95, alpha: 0.14),
            CGColor(red: 0.60, green: 0.72, blue: 0.95, alpha: 0.0)
        ] as CFArray
        if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.62),
                startRadius: 0,
                endCenter: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.56),
                endRadius: cardRect.width * 0.52,
                options: []
            )
        }

        // Crisp hairline inner rim highlight.
        ctx.addPath(tilePath)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
        ctx.setLineWidth(max(1.0, s * 0.007))
        ctx.strokePath()

        // Single-shape sculpted luminous white Eave glyph.
        let glyphInset = cardRect.width * 0.10
        let glyphRect = cardRect.insetBy(dx: glyphInset, dy: glyphInset)
        let glyphPath = makeEaveGlyphPath(in: glyphRect, opticalWeight: 1.02)

        // Sheltered downward ambient shadow cast by the eave.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.022),
            blur: s * 0.048,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        )
        ctx.addPath(glyphPath)
        ctx.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1.0))
        ctx.fillPath()
        ctx.restoreGState()

        // Refined metallic satin fill gradient inside the single eave silhouette.
        ctx.saveGState()
        ctx.addPath(glyphPath)
        ctx.clip()
        let glyphColors = [
            CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0),
            CGColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1.0)
        ] as CFArray
        if let glyphGradient = CGGradient(colorsSpace: space, colors: glyphColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                glyphGradient,
                start: CGPoint(x: glyphRect.midX, y: glyphRect.minY + glyphRect.height * 0.68),
                end: CGPoint(x: glyphRect.midX, y: glyphRect.minY + glyphRect.height * 0.30),
                options: []
            )
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }
}

func renderMenuBarIcon(pixelSize: Int, to url: URL) throws {
    try writePNG(width: pixelSize, height: pixelSize, to: url) { ctx, bounds in
        // Optically balanced stroke weight for crisp 18pt macOS menu bar readability.
        let glyphPath = makeEaveGlyphPath(in: bounds, opticalWeight: 1.24)
        ctx.addPath(glyphPath)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
        ctx.fillPath()
    }
}

// Root Assets Contents.json
let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try rootContents.write(to: assetsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// AppIcon sizes
let appIconSpecs: [(size: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

for spec in appIconSpecs {
    try renderAppIcon(pixelSize: spec.size * spec.scale, to: appIconDir.appendingPathComponent(spec.filename))
}

let appIconEntries = appIconSpecs.map { spec in
    """
        {
          "filename" : "\(spec.filename)",
          "idiom" : "mac",
          "scale" : "\(spec.scale)x",
          "size" : "\(spec.size)x\(spec.size)"
        }
    """
}.joined(separator: ",\n")

let appIconJSON = """
{
  "images" : [
\(appIconEntries)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try appIconJSON.write(to: appIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// MenuBarIcon template assets (18pt @1x, @2x, @3x)
let menuSpecs: [(scale: Int, filename: String)] = [
    (1, "menubar_18.png"),
    (2, "menubar_18@2x.png"),
    (3, "menubar_18@3x.png")
]
for spec in menuSpecs {
    try renderMenuBarIcon(pixelSize: 18 * spec.scale, to: menuBarDir.appendingPathComponent(spec.filename))
}

let menuBarJSON = """
{
  "images" : [
    {
      "filename" : "menubar_18.png",
      "idiom" : "mac",
      "scale" : "1x"
    },
    {
      "filename" : "menubar_18@2x.png",
      "idiom" : "mac",
      "scale" : "2x"
    },
    {
      "filename" : "menubar_18@3x.png",
      "idiom" : "mac",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
"""
try menuBarJSON.write(to: menuBarDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Generated refined architectural Eave AppIcon and MenuBarIcon assets.")
