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
    static let tileHeight: CGFloat = 54
    static let horizontalSpacing: CGFloat = 4
    static let verticalSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 9
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
                contentWidth: min(420, boundedMaxWidth),
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
/// Supports left-click and right-click forwarding while preserving 120fps scrolling and Dock magnification.
struct SecondRowBarView: View {
    let controller: SecondRowBarController

    private struct GridPosition: Equatable {
        let row: Int
        let col: Int
    }

    private struct ScrollEdges: Equatable {
        var canScrollLeading = false
        var canScrollTrailing = false
    }

    @State private var hoveredRowIndex: Int?
    @State private var hoveredGridPos: GridPosition?
    @State private var scrollEdges = ScrollEdges()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .preferredColorScheme(controller.appearanceMode.colorScheme)
            .onChange(of: controller.isVisible) { _, visible in
                if !visible {
                    hoveredRowIndex = nil
                    hoveredGridPos = nil
                }
            }
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
                    controller.hide()
                    controller.onRequestPermissions?()
                }
                .buttonStyle(EaveSecondaryButtonStyle())
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.items.isEmpty {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing hidden yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text("Click the Eave icon to show the • divider, then")
                        EaveKeycap(label: "⌘", fontSize: 9.5, horizontalPadding: 4.5, verticalPadding: 1.5)
                        Text("-drag icons left of it.")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                if let showDivider = controller.onRequestShowDivider {
                    Button("Show Divider") {
                        controller.hide()
                        showDivider()
                    }
                    .buttonStyle(EaveSecondaryButtonStyle(compact: true))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.layoutMode == .horizontalScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: metrics.horizontalSpacing) {
                    ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                        let mag = EaveDockMagnification.resolve(index: index, hoveredIndex: hoveredRowIndex, reduceMotion: reduceMotion)
                        SecondRowItemTile(
                            item: item,
                            badge: resolvedBadge(for: item),
                            width: metrics.tileWidth,
                            height: metrics.tileHeight,
                            magnification: mag,
                            onHoverChanged: { hovering in
                                if hovering {
                                    hoveredRowIndex = index
                                } else if hoveredRowIndex == index {
                                    hoveredRowIndex = nil
                                }
                            },
                            onSelect: { button in
                                controller.selectItem(item, button: button)
                            }
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
            }
            .onScrollGeometryChange(for: ScrollEdges.self) { geo in
                let maxOffset = geo.contentSize.width - geo.containerSize.width
                return ScrollEdges(
                    canScrollLeading: geo.contentOffset.x > 1,
                    canScrollTrailing: geo.contentOffset.x < maxOffset - 1
                )
            } action: { _, edges in
                scrollEdges = edges
            }
            .mask(edgeFadeMask)
        } else {
            let axes: Axis.Set = metrics.isVerticallyScrollable ? [.horizontal, .vertical] : .horizontal
            ScrollView(axes, showsIndicators: false) {
                multiRowGrid
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
            }
        }
    }

    /// Soft fade on whichever edge has more icons beyond it, hinting that the row scrolls.
    private var edgeFadeMask: some View {
        let fadeWidth: CGFloat = 22
        return HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(scrollEdges.canScrollLeading ? 0.0 : 1.0), .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            Rectangle().fill(Color.black)
            LinearGradient(
                colors: [.black, .black.opacity(scrollEdges.canScrollTrailing ? 0.0 : 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
    }

    private var multiRowGrid: some View {
        let rows = SecondRowLayoutMetrics.chunkedRows(controller.items, itemsPerRow: controller.itemsPerRow)
        return VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowItems in
                let activeCol = (hoveredGridPos?.row == rowIndex) ? hoveredGridPos?.col : nil
                HStack(spacing: metrics.horizontalSpacing) {
                    ForEach(Array(rowItems.enumerated()), id: \.element.id) { colIndex, item in
                        let pos = GridPosition(row: rowIndex, col: colIndex)
                        let mag = EaveDockMagnification.resolve(index: colIndex, hoveredIndex: activeCol, reduceMotion: reduceMotion)
                        SecondRowItemTile(
                            item: item,
                            badge: resolvedBadge(for: item),
                            width: metrics.tileWidth,
                            height: metrics.tileHeight,
                            magnification: mag,
                            onHoverChanged: { hovering in
                                if hovering {
                                    hoveredGridPos = pos
                                } else if hoveredGridPos == pos {
                                    hoveredGridPos = nil
                                }
                            },
                            onSelect: { button in
                                controller.selectItem(item, button: button)
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

// MARK: - Compact Skeleton & High-FPS Dual-Click Tile

private struct SecondRowSkeletonView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(reduceMotion ? 0.08 : (pulse ? 0.12 : 0.05)))
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
        .onAppear { if !reduceMotion { pulse = true } }
    }
}

private struct SecondRowItemTile: View {
    let item: MenuBarItemInfo
    let badge: String?
    let width: CGFloat
    let height: CGFloat
    let magnification: EaveDockMagnification
    let onHoverChanged: (Bool) -> Void
    let onSelect: (MenuBarClickButton) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isRightPressed = false

    private var hoverFillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(magnification.isPrimary ? 0.12 : 0.0)
        }
        return Color.black.opacity(magnification.isPrimary ? 0.075 : 0.0)
    }

    var body: some View {
        let resolved = AppIconService.shared.resolveIconOnly(for: item)
        Button {
            onSelect(.left)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    iconVisual(image: resolved.image, symbolName: resolved.symbolName)
                        .frame(width: 30, height: 30)
                        .scaleEffect(magnification.scale, anchor: .bottom)
                        .offset(y: magnification.liftY)

                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(EaveTypography.badgeFont(size: 9.0, weight: "Fredoka-Medium"))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
                            )
                            .offset(x: 5, y: -3 + magnification.liftY)
                    }
                }
                .padding(.top, 2)

                Text(item.appName)
                    .font(.system(size: 10, weight: magnification.isPrimary ? .medium : .regular))
                    .foregroundStyle(.primary.opacity(magnification.isPrimary || contrast == .increased ? 1.0 : 0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: width - 6)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hoverFillColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(isRightPressed ? 0.88 : 1.0)
            .opacity(isRightPressed ? 0.84 : 1.0)
            .animation(EaveMotion.pressSpring, value: isRightPressed)
            .animation(EaveMotion.dockWave, value: magnification)
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.88, pressedOpacity: 0.84))
        .overlay(
            RightClickCatcherView(
                onPressChanged: { isRightPressed = $0 },
                onRightClick: { onSelect(.right) }
            )
        )
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .accessibilityLabel(badge.map { "\(item.searchableText), \($0) new" } ?? item.searchableText)
        .accessibilityHint("Double-tap to open. Use the actions menu for a right-click.")
        .accessibilityAction(named: "Right-click") { onSelect(.right) }
    }

    @ViewBuilder
    private func iconVisual(image: NSImage?, symbolName: String?) -> some View {
        if let appIcon = image {
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

/// Zero-overhead AppKit overlay that intercepts ONLY right-mouse events (letting hover, scroll, and left-click
/// pass through untouched to SwiftUI for 120fps scrolling and Dock magnification).
private struct RightClickCatcherView: NSViewRepresentable {
    let onPressChanged: (Bool) -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickCatcherNSView {
        let view = RightClickCatcherNSView()
        view.onPressChanged = onPressChanged
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickCatcherNSView, context: Context) {
        nsView.onPressChanged = onPressChanged
        nsView.onRightClick = onRightClick
    }
}

private final class RightClickCatcherNSView: NSView {
    var onPressChanged: ((Bool) -> Void)?
    var onRightClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        case .leftMouseDown where event.modifierFlags.contains(.control):
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onPressChanged?(true)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onPressChanged?(false)
            let local = convert(event.locationInWindow, from: nil)
            if bounds.contains(local) {
                onRightClick?()
            }
            return
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onPressChanged?(true)
    }

    override func rightMouseUp(with event: NSEvent) {
        onPressChanged?(false)
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            onRightClick?()
        }
    }
}
