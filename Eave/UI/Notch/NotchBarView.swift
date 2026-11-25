import AppKit
import SwiftUI

/// Phase 3 Notch Bar: downward-expanding drawer inside the notch housing hidden menu bar items.
struct NotchBarView: View {
    let items: [CapturedMenuBarItem]
    let isLoading: Bool
    let notchHeight: CGFloat
    let onSelectItem: (MenuBarItemInfo) -> Void
    let onRefresh: () -> Void
    let onOpenSearch: () -> Void
    let onClose: () -> Void

    @State private var hoveredItemID: String?

    private var hiddenItems: [CapturedMenuBarItem] {
        items.filter { $0.info.section != .visible }
    }

    private var displayItems: [CapturedMenuBarItem] {
        hiddenItems.isEmpty ? items : hiddenItems
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header aligned cleanly beside the notch ears.
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 5, height: 5)
                    Text(hiddenItems.isEmpty ? "Menu Bar" : "Hidden Under Eave")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                HStack(spacing: 6) {
                    barHeaderButton(symbol: "magnifyingglass", help: "Search Menu Bar") {
                        onOpenSearch()
                    }
                    barHeaderButton(symbol: "arrow.clockwise", help: "Refresh Items") {
                        onRefresh()
                    }
                    barHeaderButton(symbol: "xmark", help: "Close Notch Bar") {
                        onClose()
                    }
                }
            }
            .frame(height: max(notchHeight, 30))
            .padding(.horizontal, 20)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.horizontal, 16)

            if isLoading && displayItems.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                    Text("Scanning menu bar items...")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 82)
            } else if displayItems.isEmpty {
                VStack(spacing: 4) {
                    Text("No hidden items detected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Hold ⌘ and drag icons left of Eave's divider to tuck them here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: 82)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayItems) { captured in
                            notchBarItemTile(captured)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .frame(height: 84)
            }
        }
        .padding(.bottom, 6)
    }

    private func notchBarItemTile(_ captured: CapturedMenuBarItem) -> some View {
        let isHovered = hoveredItemID == captured.id
        return Button {
            onSelectItem(captured.info)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.18 : 0.08))
                        .frame(width: 42, height: 34)

                    if let image = captured.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 26, maxHeight: 22)
                    } else {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Text(captured.info.appName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.98 : 0.72))
                    .lineLimit(1)
                    .frame(width: 58)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItemID = hovering ? captured.id : (hoveredItemID == captured.id ? nil : hoveredItemID)
        }
        .help(captured.info.searchableText)
    }

    private func barHeaderButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
