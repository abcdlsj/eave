import AppKit
import SwiftUI

/// Pure geometry, row-chunking, horizontal/multi-row layout, screen-clamping, and hover-bridge calculations
/// for the Second-Row Bar. Isolated as pure functions for deterministic unit testing.
struct SecondRowLayoutMetrics: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let visibleRows: Int
    let isHorizontallyScrollable: Bool
    let isVerticallyScrollable: Bool
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    static let tileWidth: CGFloat = 54
    static let tileHeight: CGFloat = 52
    static let horizontalSpacing: CGFloat = 4
    static let verticalSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let maxVisibleRows: Int = 4
    static let defaultMaxContentWidth: CGFloat = 760

    static func resolve(
        itemCount: Int,
        itemsPerRow: Int,
        layoutMode: SecondRowLayoutMode = .horizontalScroll,
        maxContentWidth: CGFloat = SecondRowLayoutMetrics.defaultMaxContentWidth
    ) -> SecondRowLayoutMetrics {
        let clampedPerRow = EaveSettings.clampedItemsPerRow(itemsPerRow)
        let boundedMaxWidth = max(maxContentWidth, tileWidth + horizontalPadding * 2)

        guard itemCount > 0 else {
            return SecondRowLayoutMetrics(
                columns: 0,
                rows: 0,
                visibleRows: 0,
                isHorizontallyScrollable: false,
                isVerticallyScrollable: false,
                contentWidth: min(312, boundedMaxWidth),
                contentHeight: 46,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        }

        switch layoutMode {
        case .horizontalScroll:
            let visibleColumns = min(itemCount, clampedPerRow)
            let rawWidth = CGFloat(visibleColumns) * tileWidth
                + CGFloat(max(visibleColumns - 1, 0)) * horizontalSpacing
                + horizontalPadding * 2
            let width = min(rawWidth, boundedMaxWidth)
            let height = tileHeight + verticalPadding * 2
            let fullRowWidth = CGFloat(itemCount) * tileWidth
                + CGFloat(max(itemCount - 1, 0)) * horizontalSpacing
                + horizontalPadding * 2

            return SecondRowLayoutMetrics(
                columns: visibleColumns,
                rows: 1,
                visibleRows: 1,
                isHorizontallyScrollable: fullRowWidth > width + 0.5,
                isVerticallyScrollable: false,
                contentWidth: width,
                contentHeight: height,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )

        case .multiRow:
            let columns = min(itemCount, clampedPerRow)
            let rows = Int(ceil(Double(itemCount) / Double(clampedPerRow)))
            let visibleRows = min(rows, maxVisibleRows)
            let rawWidth = CGFloat(columns) * tileWidth
                + CGFloat(max(columns - 1, 0)) * horizontalSpacing
                + horizontalPadding * 2
            let width = min(rawWidth, boundedMaxWidth)
            let height = CGFloat(visibleRows) * tileHeight
                + CGFloat(max(visibleRows - 1, 0)) * verticalSpacing
                + verticalPadding * 2

            return SecondRowLayoutMetrics(
                columns: columns,
                rows: rows,
                visibleRows: visibleRows,
                isHorizontallyScrollable: rawWidth > width + 0.5,
                isVerticallyScrollable: rows > maxVisibleRows,
                contentWidth: width,
                contentHeight: height,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        }
    }

    /// Splits items into ordered rows of at most `itemsPerRow` elements.
    static func chunkedRows<T>(_ items: [T], itemsPerRow: Int) -> [[T]] {
        let size = EaveSettings.clampedItemsPerRow(itemsPerRow)
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: size).map { start in
            Array(items[start..<min(start + size, items.count)])
        }
    }

    /// Computes the AppKit screen-space frame for the floating panel directly beneath the menu bar,
    /// anchored neatly to the Eave icon and clamped within the display's visible bounds.
    static func panelFrame(
        contentSize: CGSize,
        anchorFrame: CGRect?,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        menuBarHeight: CGFloat,
        verticalGap: CGFloat = 6,
        horizontalMargin: CGFloat = 12
    ) -> CGRect {
        let resolvedBarHeight = max(menuBarHeight, 24)
        let menuBarBottomY = screenFrame.maxY - resolvedBarHeight
        let visualTopY = menuBarBottomY - verticalGap
        let originY = visualTopY - contentSize.height

        let desiredMinX: CGFloat
        if let anchor = anchorFrame {
            // Right-align gently beneath Eave's icon so hidden items cascade leftward like the real menu bar.
            desiredMinX = anchor.maxX - contentSize.width + 6
        } else {
            desiredMinX = visibleFrame.maxX - contentSize.width - horizontalMargin
        }

        let minX = visibleFrame.minX + horizontalMargin
        let maxX = max(minX, visibleFrame.maxX - contentSize.width - horizontalMargin)
        let clampedX = min(max(desiredMinX, minX), maxX)

        return CGRect(
            x: round(clampedX),
            y: round(originY),
            width: round(contentSize.width),
            height: round(contentSize.height)
        )
    }

    /// Returns true if `point` lies inside the Eave toggle icon, the second-row card,
    /// or the vertical hover-bridge corridor connecting them (preventing premature dismissal while moving down).
    static func isPointInHoverSafeZone(
        _ point: CGPoint,
        anchorFrame: CGRect?,
        cardScreenFrame: CGRect
    ) -> Bool {
        if cardScreenFrame.insetBy(dx: -10, dy: -10).contains(point) {
            return true
        }
        if let anchor = anchorFrame {
            if anchor.insetBy(dx: -8, dy: -8).contains(point) {
                return true
            }
            let bridgeMinX = min(anchor.minX, cardScreenFrame.minX) - 6
            let bridgeMaxX = max(anchor.maxX, cardScreenFrame.maxX) + 6
            let bridgeMinY = cardScreenFrame.maxY - 4
            let bridgeMaxY = anchor.minY + 4
            if bridgeMaxY >= bridgeMinY {
                let bridge = CGRect(
                    x: bridgeMinX,
                    y: bridgeMinY,
                    width: bridgeMaxX - bridgeMinX,
                    height: bridgeMaxY - bridgeMinY
                )
                if bridge.contains(point) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Second-Row Floating Bar SwiftUI View

/// High-FPS floating second-row menu bar directly beneath the macOS menu bar.
/// Engineered for zero offscreen GPU passes:
/// - Shadow is composited natively by WindowServer (`panel.hasShadow = true`), never via animated SwiftUI `.shadow`.
/// - Panel fade uses hardware `NSWindow.alphaValue` instead of scaling live `.glassEffect` / blur layers.
/// - Supports silky 120fps horizontal scrolling and configurable multi-row wrapping.
struct SecondRowBarView: View {
    let controller: SecondRowBarController

    private var metrics: SecondRowLayoutMetrics {
        SecondRowLayoutMetrics.resolve(
            itemCount: controller.items.count,
            itemsPerRow: controller.itemsPerRow,
            layoutMode: controller.layoutMode,
            maxContentWidth: controller.maxContentWidth
        )
    }

    var body: some View {
        cardBody
            .frame(width: metrics.contentWidth, height: metrics.contentHeight)
            .eaveGlassSurface(cornerRadius: 14)
    }

    @ViewBuilder
    private var cardBody: some View {
        if controller.isScanning && controller.items.isEmpty {
            SecondRowSkeletonView()
        } else if controller.items.isEmpty && controller.needsAccessibilityPermission {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Grant Accessibility to list hidden items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Grant") {
                    EaveHaptics.tick()
                    controller.hide()
                    controller.onRequestPermissions?()
                }
                .buttonStyle(EaveSecondaryButtonStyle())
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.items.isEmpty {
            HStack(spacing: 6) {
                Text("Hold")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                EaveKeycap(label: "⌘", fontSize: 9.5, horizontalPadding: 4.5, verticalPadding: 1.5)
                Text("and drag icons left of the dot to hide")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.layoutMode == .horizontalScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: metrics.horizontalSpacing) {
                    ForEach(controller.items) { captured in
                        SecondRowItemTile(
                            captured: captured,
                            badge: resolvedBadge(for: captured.info),
                            width: metrics.tileWidth,
                            height: metrics.tileHeight,
                            onSelect: {
                                EaveHaptics.tick()
                                controller.selectItem(captured.info)
                            }
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
            }
        } else {
            let axes: Axis.Set = metrics.isVerticallyScrollable ? [.horizontal, .vertical] : .horizontal
            ScrollView(axes, showsIndicators: false) {
                multiRowGrid
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
            }
        }
    }

    private var multiRowGrid: some View {
        let rows = SecondRowLayoutMetrics.chunkedRows(controller.items, itemsPerRow: controller.itemsPerRow)
        return VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                HStack(spacing: metrics.horizontalSpacing) {
                    ForEach(rowItems) { captured in
                        SecondRowItemTile(
                            captured: captured,
                            badge: resolvedBadge(for: captured.info),
                            width: metrics.tileWidth,
                            height: metrics.tileHeight,
                            onSelect: {
                                EaveHaptics.tick()
                                controller.selectItem(captured.info)
                            }
                        )
                    }
                }
            }
        }
    }

    private func resolvedBadge(for info: MenuBarItemInfo) -> String? {
        if let bundleID = info.bundleIdentifier, let dockBadge = controller.activeBadges[bundleID], !dockBadge.isEmpty {
            return dockBadge
        }
        let title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.count <= 4, title.allSatisfy(\.isNumber) {
            return title
        }
        return nil
    }
}

// MARK: - Compact Skeleton & High-FPS Tile

private struct SecondRowSkeletonView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(pulse ? 0.12 : 0.05))
                    .frame(width: 28, height: 28)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: pulse
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}

private struct SecondRowItemTile: View {
    let captured: CapturedMenuBarItem
    let badge: String?
    let width: CGFloat
    let height: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        let resolved = AppIconService.shared.resolveIconOnly(for: captured.info)
        Button(action: onSelect) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    iconVisual(image: resolved.image, symbolName: resolved.symbolName)
                        .frame(width: 30, height: 30)
                        .scaleEffect(isHovered ? 1.07 : 1.0)

                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
                            )
                            .offset(x: 5, y: -3)
                    }
                }

                Text(captured.info.appName)
                    .font(.system(size: 9.5, weight: isHovered ? .medium : .regular))
                    .foregroundStyle(.primary.opacity(isHovered ? 0.95 : 0.68))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: width - 6)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0.0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.90, pressedOpacity: 0.85))
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(captured.info.searchableText)
    }

    @ViewBuilder
    private func iconVisual(image: NSImage?, symbolName: String?) -> some View {
        if captured.isLiveCapture, let live = captured.image {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 28, height: 24)
                Image(nsImage: live)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 22, maxHeight: 18)
            }
        } else if let appIcon = image {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 26, height: 26)
                Image(systemName: symbolName ?? "menubar.rectangle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.80))
            }
        }
    }
}
