import AppKit
import SwiftUI

/// Crafted Notch Bar drawer: a miniature obsidian Dock tucked seamlessly beneath the MacBook notch.
/// Optimized for 120fps ProMotion scrolling and hover:
/// - Hover state is strictly local per tile (zero parent invalidation).
/// - Edge fade uses static obsidian overlays instead of an offscreen ScrollView alpha mask.
/// - Pre-rasterized 72px icons with zero per-tile offscreen drop shadows.
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

    private var displayItems: [CapturedMenuBarItem] {
        let hidden = items.filter { $0.info.section != .visible }
        return hidden.isEmpty ? items : hidden
    }

    private var hiddenCount: Int {
        items.reduce(into: 0) { count, item in
            if item.info.section != .visible { count += 1 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top wing bar flanking the physical camera housing cleanly.
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image("MenuBarIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(headerTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)

                Spacer(minLength: max(notchWidth - 20, 120))
                    .frame(width: max(notchWidth - 20, 120))

                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    NotchHeaderIconButton(symbol: "magnifyingglass", helpText: "Search Menu Bar (⌥⌘K)", action: onOpenSearch)
                    NotchHeaderIconButton(symbol: "arrow.clockwise", helpText: "Refresh", action: onRefresh)
                    NotchHeaderIconButton(symbol: "gearshape", helpText: "Settings", action: onOpenSettings)
                    NotchHeaderIconButton(symbol: "xmark", helpText: "Close", action: onClose)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 18)
            }
            .frame(height: max(notchHeight, 34))

            LinearGradient(
                colors: [.clear, .white.opacity(0.10), .white.opacity(0.10), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.6)
            .padding(.horizontal, 14)

            shelfContent
                .frame(height: 90)
        }
        .padding(.bottom, 8)
    }

    private var headerTitle: String {
        if hiddenCount > 0 {
            return "\(hiddenCount) Under Eave"
        }
        return items.isEmpty ? "Eave" : "\(items.count) Items"
    }

    @ViewBuilder
    private var shelfContent: some View {
        let currentItems = displayItems
        if isLoading && currentItems.isEmpty {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text("Scanning menu bar...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentItems.isEmpty {
            VStack(spacing: 5) {
                Text("Nothing tucked under Eave yet")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                Text("Hold ⌘ and drag icons left of Eave's divider to tuck them here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.46))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(currentItems) { captured in
                            NotchBarIconTile(
                                captured: captured,
                                badge: resolvedBadge(for: captured.info),
                                onSelect: { onSelectItem(captured.info) }
                            )
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                }

                // Zero-cost edge fade overlays matching pure black obsidian (replaces expensive ScrollView.mask).
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 22)
                    Spacer()
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 22)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Prefers live Dock badge; falls back to compact numeric AX menu bar title (e.g. WeCom unread count).
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

// MARK: - Self-Contained High-FPS App Icon Tile

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
                    // Lightweight GPU radial aura & hover pad (only drawn when hovered).
                    if isHovered {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [resolved.accentColor.opacity(0.28), .clear],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 26
                                )
                            )
                            .frame(width: 50, height: 50)

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                            )
                            .frame(width: 44, height: 44)
                    }

                    iconVisual
                        .frame(width: 44, height: 44)
                        .scaleEffect(isHovered ? 1.08 : 1.0)

                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.96, green: 0.27, blue: 0.29))
                                    .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.2))
                            )
                            .offset(x: 3, y: -3)
                    }
                }
                .frame(width: 46, height: 46)

                Text(captured.info.appName)
                    .font(.system(size: 10, weight: isHovered ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isHovered ? 0.96 : 0.56))
                    .lineLimit(1)
                    .frame(width: 58)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help(captured.info.searchableText)
    }

    @ViewBuilder
    private var iconVisual: some View {
        if captured.isLiveCapture, let live = captured.image {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.14))
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [resolved.accentColor.opacity(0.28), resolved.accentColor.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(resolved.accentColor.opacity(0.30), lineWidth: 0.6)
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: resolved.symbolName ?? "menubar.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(resolved.accentColor)
            }
        }
    }
}

private struct NotchHeaderIconButton: View {
    let symbol: String
    let helpText: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.96 : 0.60))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.white.opacity(hovering ? 0.16 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }
}
