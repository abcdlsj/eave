import AppKit
import SwiftUI

/// Crafted Notch Bar drawer: a miniature obsidian Dock tucked seamlessly beneath the MacBook notch.
/// Features crisp high-res App Icons, per-app dominant color hover halos, smooth spring lift,
/// live unread badge overlays, and edge-faded scrolling.
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

    @State private var hoveredItemID: String?

    private var hiddenItems: [CapturedMenuBarItem] {
        items.filter { $0.info.section != .visible }
    }

    private var displayItems: [CapturedMenuBarItem] {
        hiddenItems.isEmpty ? items : hiddenItems
    }

    private var hoveredItem: CapturedMenuBarItem? {
        guard let hoveredItemID else { return nil }
        return displayItems.first(where: { $0.id == hoveredItemID })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top wing bar flanking the physical camera housing cleanly.
            HStack(spacing: 0) {
                // Left ear: minimalist Eave glyph / active hover name.
                HStack(spacing: 6) {
                    Image("MenuBarIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(headerTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)

                // Clear reserve directly over the hardware camera.
                Spacer(minLength: max(notchWidth - 20, 120))
                    .frame(width: max(notchWidth - 20, 120))

                // Right ear: crisp minimalist controls.
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    barControl(symbol: "magnifyingglass", help: "Search Menu Bar (⌥⌘K)", action: onOpenSearch)
                    barControl(symbol: "arrow.clockwise", help: "Refresh", action: onRefresh)
                    barControl(symbol: "gearshape", help: "Settings", action: onOpenSettings)
                    barControl(symbol: "xmark", help: "Close", action: onClose)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 18)
            }
            .frame(height: max(notchHeight, 34))

            // Hairline separator fading softly at both edges.
            LinearGradient(
                colors: [.clear, .white.opacity(0.10), .white.opacity(0.10), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.6)
            .padding(.horizontal, 14)

            // Icon shelf area.
            shelfContent
                .frame(height: 92)
        }
        .padding(.bottom, 8)
    }

    private var headerTitle: String {
        if let hovered = hoveredItem {
            return hovered.info.appName
        }
        if hiddenItems.isEmpty {
            return displayItems.isEmpty ? "Eave" : "\(displayItems.count) Items"
        }
        return "\(hiddenItems.count) Under Eave"
    }

    @ViewBuilder
    private var shelfContent: some View {
        if isLoading && displayItems.isEmpty {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text("Scanning menu bar...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayItems.isEmpty {
            VStack(spacing: 5) {
                Text("Nothing tucked under Eave yet")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                Text("Hold ⌘ and drag icons left of Eave's divider, or grant Accessibility for full discovery.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.46))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayItems) { captured in
                        NotchBarIconTile(
                            captured: captured,
                            badge: resolvedBadge(for: captured.info),
                            isHovered: hoveredItemID == captured.id,
                            onSelect: { onSelectItem(captured.info) }
                        )
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                if hovering {
                                    hoveredItemID = captured.id
                                } else if hoveredItemID == captured.id {
                                    hoveredItemID = nil
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
            }
            // Subtle fade mask at horizontal edges so icons melt into obsidian instead of clipping harshly.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private func barControl(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        NotchHeaderIconButton(symbol: symbol, helpText: help, action: action)
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

// MARK: - Crafted App Icon Tile

private struct NotchBarIconTile: View {
    let captured: CapturedMenuBarItem
    let badge: String?
    let isHovered: Bool
    let onSelect: () -> Void

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(for: captured.info)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    // GPU-native radial color aura on hover (zero offscreen Gaussian blur cost).
                    if isHovered {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [resolved.accentColor.opacity(0.32), .clear],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 28
                                )
                            )
                            .frame(width: 54, height: 54)
                    }

                    // Subtle machined hover pad (invisible at rest so icons float cleanly like a Dock).
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.10 : 0.0))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(isHovered ? 0.15 : 0.0), lineWidth: 0.6)
                        )
                        .frame(width: 46, height: 46)

                    iconVisual
                        .frame(width: 46, height: 46)
                        .scaleEffect(isHovered ? 1.09 : 1.0)
                        .offset(y: isHovered ? -1.5 : 0)

                    // Live unread badge dot/count overlaid cleanly on top-right corner.
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
        }
        .buttonStyle(.plain)
        .help(captured.info.searchableText)
    }

    @ViewBuilder
    private var iconVisual: some View {
        if captured.isLiveCapture, let live = captured.image {
            // When user explicitly enables live pixel capture, frame on a balanced glass pill
            // so dark menu bar icons stay crisp and legible against obsidian.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 36, height: 32)
                Image(nsImage: live)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 26, maxHeight: 22)
            }
        } else if let appIcon = resolved.image {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2.5)
        } else {
            // Crafted glass-tinted squircle for macOS system extras (Wi-Fi, Bluetooth, Battery, etc.).
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [resolved.accentColor.opacity(0.30), resolved.accentColor.opacity(0.13)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(resolved.accentColor.opacity(0.32), lineWidth: 0.65)
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: resolved.symbolName ?? "menubar.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(resolved.accentColor)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
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
