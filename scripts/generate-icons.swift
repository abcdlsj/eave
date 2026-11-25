#!/usr/bin/env swift

import AppKit
import Foundation

// Generates minimalist single-shape Eave icons for AppIcon.appiconset and MenuBarIcon.imageset.
// Geometry: a single continuous architectural eave silhouette with a subtle central notch overhang.

let fileManager = FileManager.default
let rootDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let assetsDir = rootDir.appendingPathComponent("Eave/Resources/Assets.xcassets")
let appIconDir = assetsDir.appendingPathComponent("AppIcon.appiconset")
let menuBarDir = assetsDir.appendingPathComponent("MenuBarIcon.imageset")

try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: menuBarDir, withIntermediateDirectories: true)

/// Returns the canonical single-shape Eave glyph path normalized inside `rect`.
/// Shape: clean horizontal eave bar with softly rounded corners and a centered inverted-notch overhang.
func makeEaveGlyphPath(in rect: CGRect) -> CGPath {
    let w = rect.width
    let h = rect.height
    let ox = rect.minX
    let oy = rect.minY

    // Coordinates in standard AppKit/CoreGraphics bottom-up space (y increases upward).
    let topY = oy + h * 0.72
    let barBottomY = oy + h * 0.50
    let notchBottomY = oy + h * 0.28

    let leftX = ox + w * 0.08
    let rightX = ox + w * 0.92

    let notchLeftTopX = ox + w * 0.30
    let notchLeftBotX = ox + w * 0.36
    let notchRightBotX = ox + w * 0.64
    let notchRightTopX = ox + w * 0.70

    let outerR = w * 0.085
    let innerR = w * 0.065
    let notchR = w * 0.075

    let path = CGMutablePath()
    // Start at top-left after top-left corner curve.
    path.move(to: CGPoint(x: leftX + outerR, y: topY))
    // Top edge to top-right.
    path.addArc(tangent1End: CGPoint(x: rightX, y: topY),
                tangent2End: CGPoint(x: rightX, y: barBottomY),
                radius: outerR)
    // Right edge down to right underside of eave.
    path.addArc(tangent1End: CGPoint(x: rightX, y: barBottomY),
                tangent2End: CGPoint(x: notchRightTopX, y: barBottomY),
                radius: outerR)
    // Underside of right eave curving smoothly into the central notch drop.
    path.addArc(tangent1End: CGPoint(x: notchRightTopX, y: barBottomY),
                tangent2End: CGPoint(x: notchRightBotX, y: notchBottomY),
                radius: innerR)
    // Right wall of central notch into notch bottom.
    path.addArc(tangent1End: CGPoint(x: notchRightBotX, y: notchBottomY),
                tangent2End: CGPoint(x: notchLeftBotX, y: notchBottomY),
                radius: notchR)
    // Left wall of central notch rising back up.
    path.addArc(tangent1End: CGPoint(x: notchLeftBotX, y: notchBottomY),
                tangent2End: CGPoint(x: notchLeftTopX, y: barBottomY),
                radius: notchR)
    // Transition back out to left eave underside.
    path.addArc(tangent1End: CGPoint(x: notchLeftTopX, y: barBottomY),
                tangent2End: CGPoint(x: leftX, y: barBottomY),
                radius: innerR)
    // Left eave underside wrapping up left edge.
    path.addArc(tangent1End: CGPoint(x: leftX, y: barBottomY),
                tangent2End: CGPoint(x: leftX, y: topY),
                radius: outerR)
    // Close top-left corner.
    path.addArc(tangent1End: CGPoint(x: leftX, y: topY),
                tangent2End: CGPoint(x: leftX + outerR, y: topY),
                radius: outerR)
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

        // Deep obsidian rounded-square icon tile.
        let tilePath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()

        let colors = [
            CGColor(red: 0.145, green: 0.152, blue: 0.172, alpha: 1.0),
            CGColor(red: 0.068, green: 0.072, blue: 0.084, alpha: 1.0)
        ] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
                end: CGPoint(x: cardRect.midX, y: cardRect.minY),
                options: []
            )
        }

        // Subtle inner rim highlight.
        ctx.addPath(tilePath)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        ctx.setLineWidth(max(1.0, s * 0.008))
        ctx.strokePath()
        ctx.restoreGState()

        // Single-shape pure white Eave glyph centered on tile.
        let glyphInset = cardRect.width * 0.16
        let glyphRect = cardRect.insetBy(dx: glyphInset, dy: glyphInset)
        let glyphPath = makeEaveGlyphPath(in: glyphRect)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.015),
            blur: s * 0.035,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
        )
        ctx.addPath(glyphPath)
        ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1.0))
        ctx.fillPath()
        ctx.restoreGState()
    }
}

func renderMenuBarIcon(pixelSize: Int, to url: URL) throws {
    try writePNG(width: pixelSize, height: pixelSize, to: url) { ctx, bounds in
        let glyphPath = makeEaveGlyphPath(in: bounds)
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

print("Generated AppIcon and MenuBarIcon assets successfully.")
