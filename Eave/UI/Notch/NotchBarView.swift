import AppKit
import SwiftUI

/// Crafted Notch Bar drawer: a serene, pure-obsidian miniature Dock tucked beneath the MacBook notch.
/// Engineered for 120fps ProMotion scrolling and hover:
/// - Hover & press states are strictly local per tile (zero parent invalidation).
/// - Edge fade uses static pure-black overlays instead of an offscreen ScrollView alpha mask.
/// - Zero neon blobs: pure monochrome obsidian lets native macOS App Icons shine cleanly.
struct NotchBarView: View {
    let items: [CapturedMenuBarItem]
    let activeBadges: [String: String]
    let isLoading: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onSelectItem: (MenuBarItemInfo) -> Void
    let onRefresh: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var showAllItems = false

    private var hiddenItems: [CapturedMenuBarItem] {
        items.filter { $0.info.section != .visible }
    }

    private var hasBothSections: Bool {
        !hiddenItems.isEmpty && hiddenItems.count < items.count
    }

    private var displayItems: [CapturedMenuBarItem] {
        if showAllItems || hiddenItems.isEmpty {
            return items
        }
        return hiddenItems
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top wing bar flanking the physical camera housing cleanly.
            HStack(spacing: 0) {
                leftHeaderWing
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)

                Spacer(minLength: max(notchWidth - 18, 120))
                    .frame(width: max(notchWidth - 18, 120))

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    EaveNotchIconButton(
                        symbol: "magnifyingglass",
                        helpText: "Search Menu Bar (⌥⌘K)",
                        action: onOpenSearch
                    )
                    EaveNotchIconButton(
                        symbol: "arrow.clockwise",
                        helpText: "Refresh",
                        spinOnClick: true,
                        action: onRefresh
                    )
                    EaveNotchIconButton(
                        symbol: "gearshape",
                        helpText: "Settings",
                        action: onOpenSettings
                    )
                    EaveNotchIconButton(
                        symbol: "xmark",
                        helpText: "Close",
                        action: onClose
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 18)
            }
            .frame(height: max(notchHeight, 36))

            Rectangle()
                .fill(Color.white.opacity(0.065))
                .frame(height: 0.5)
                .padding(.horizontal, 18)

            shelfContent
                .frame(height: 90)
        }
        .padding(.bottom, 7)
    }

    @ViewBuilder
    private var leftHeaderWing: some View {
        HStack(spacing: 10) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 13.5, height: 13.5)
                .foregroundStyle(.white.opacity(0.62))

            if hasBothSections {
                // Whisper-clean Swiss typographic switcher (Hidden / All)
                HStack(spacing: 10) {
                    headerTabButton(title: "Hidden", isActive: !showAllItems) {
                        if showAllItems {
                            EaveHaptics.tick()
                            withAnimation(EaveMotion.microSpring) { showAllItems = false }
                        }
                    }
                    headerTabButton(title: "All", isActive: showAllItems) {
                        if !showAllItems {
                            EaveHaptics.tick()
                            withAnimation(EaveMotion.microSpring) { showAllItems = true }
                        }
                    }
                }
            } else {
                Text(hiddenItems.isEmpty ? "Eave" : "Under Eave")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
        }
    }

    private func headerTabButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isActive ? 0.94 : 0.36))
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.94))
    }

    @ViewBuilder
    private var shelfContent: some View {
        let currentItems = displayItems
        if isLoading && currentItems.isEmpty {
            NotchBarSkeletonShelf()
        } else if currentItems.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing tucked under Eave yet")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))

                HStack(spacing: 5) {
                    Text("Hold")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                    EaveKeycap(label: "⌘", fontSize: 9.5, horizontalPadding: 4.5, verticalPadding: 1.5, isDarkSurface: true)
                    Text("and drag icons left of the divider to tuck them here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(currentItems) { captured in
                            NotchBarIconTile(
                                captured: captured,
                                badge: resolvedBadge(for: captured.info),
                                onSelect: {
                                    EaveHaptics.tick()
                                    onSelectItem(captured.info)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }

                // Zero-cost edge fade overlays matching pure black obsidian.
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                    Spacer()
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func resolvedBadge(for info: MenuBarItemInfo) -> String? {
        if let bundleID = info.bundleIdentifier, let dockBadge = activeBadges[bundleID], !dockBadge.isEmpty {
            return dockBadge
        }
        let title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.count <= 4, title.allSatisfy(\.isNumber) {
            return title
        }
        return nil
    }
}

// MARK: - Subtle Obsidian Skeleton Shelf

private struct NotchBarSkeletonShelf: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(pulse ? 0.08 : 0.035))
                        .frame(width: 36, height: 36)

                    Capsule()
                        .fill(Color.white.opacity(pulse ? 0.07 : 0.03))
                        .frame(width: 32, height: 5)
                }
                .animation(
                    .easeInOut(duration: 0.95)
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

// MARK: - Self-Contained High-FPS Dock Icon Tile

private struct NotchBarIconTile: View {
    let captured: CapturedMenuBarItem
    let badge: String?
    let onSelect: () -> Void

    @State private var isHovered = false

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(for: captured.info)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    // Clean, restrained frosted neutral hover tile — zero garish color blobs.
                    if isHovered {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.085))
                            .frame(width: 46, height: 46)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }

                    iconVisual
                        .frame(width: 46, height: 46)
                        .scaleEffect(isHovered ? 1.09 : 1.0)
                        .offset(y: isHovered ? -2 : 0)

                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
                                    .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.25))
                            )
                            .offset(x: 3, y: isHovered ? -5 : -3)
                    }
                }
                .frame(width: 48, height: 48)

                Text(captured.info.appName)
                    .font(.system(size: 10, weight: isHovered ? .medium : .regular))
                    .foregroundStyle(.white.opacity(isHovered ? 0.94 : 0.48))
                    .lineLimit(1)
                    .frame(width: 60)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.89, pressedOpacity: 0.85))
        .onHover { hovering in
            withAnimation(EaveMotion.microSpring) {
                isHovered = hovering
            }
        }
        .help(captured.info.searchableText)
    }

    @ViewBuilder
    private var iconVisual: some View {
        if captured.isLiveCapture, let live = captured.image {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.11))
                    .frame(width: 36, height: 32)
                Image(nsImage: live)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 26, maxHeight: 22)
            }
        } else if let appIcon = resolved.image {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 34, height: 34)

                Image(systemName: resolved.symbolName ?? "menubar.rectangle")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
    }
}
