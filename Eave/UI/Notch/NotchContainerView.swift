import SwiftUI

/// Root SwiftUI surface hosted inside NotchPanel, seamlessly fusing with the hardware notch bezel
/// and morphing smoothly across `idle`, `ambient`, `peek`, and `bar` states.
struct NotchContainerView: View {
    let stateMachine: NotchStateMachine
    let geometryProvider: () -> NotchGeometry
    let capturedItemsProvider: () -> [CapturedMenuBarItem]
    let activeBadgesProvider: () -> [String: String]
    let isScanningProvider: () -> Bool

    let onSelectBarItem: (MenuBarItemInfo) -> Void
    let onRefreshBar: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    let onAlertAction: (NotchAlert) -> Void
    let onAmbientAction: (AmbientIndicator) -> Void

    private var geometry: NotchGeometry { geometryProvider() }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: stateMachine.state)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var notchBody: some View {
        let baseW = geometry.notchRect.width
        let baseH = geometry.notchRect.height

        switch stateMachine.state {
        case .idle:
            Color.clear
                .frame(width: baseW, height: 1)

        case .ambient(let indicators):
            ambientWings(indicators: indicators, baseW: baseW, baseH: baseH)
                .background(notchShell(topRadius: 9, bottomRadius: 13))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))

        case .peek(let alert, let expanded):
            NotchPeekView(
                alert: alert,
                expanded: expanded,
                notchWidth: baseW,
                notchHeight: baseH,
                onPrimaryAction: { onAlertAction(alert) },
                onDismiss: { stateMachine.dismissPeek() }
            )
            .frame(
                width: expanded ? max(baseW + 200, 396) : baseW + 132,
                alignment: .top
            )
            .background(notchShell(topRadius: expanded ? 14 : 10, bottomRadius: expanded ? 24 : 15))
            .shadow(color: .black.opacity(expanded ? 0.48 : 0.25), radius: expanded ? 24 : 10, y: expanded ? 10 : 4)

        case .bar:
            NotchBarView(
                items: capturedItemsProvider(),
                activeBadges: activeBadgesProvider(),
                isLoading: isScanningProvider(),
                notchWidth: baseW,
                notchHeight: baseH,
                onSelectItem: onSelectBarItem,
                onRefresh: onRefreshBar,
                onOpenSearch: onOpenSearch,
                onOpenSettings: onOpenSettings,
                onClose: { stateMachine.closeBar() }
            )
            .frame(width: 520, alignment: .top)
            .background(notchShell(topRadius: 15, bottomRadius: 24))
            .shadow(color: .black.opacity(0.52), radius: 28, y: 12)
        }
    }

    private func ambientWings(indicators: [AmbientIndicator], baseW: CGFloat, baseH: CGFloat) -> some View {
        let primary = indicators.first
        let resolved = AppIconService.shared.resolve(
            bundleIdentifier: primary?.bundleIdentifier,
            fallbackSymbol: primary?.symbolName,
            fallbackAccentHex: primary?.accentHex
        )

        return HStack(spacing: 0) {
            // Left ear: crisp micro App Icon or subtle colored pulse dot.
            ZStack {
                if let img = resolved.image {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                } else {
                    Circle()
                        .fill(resolved.accentColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: resolved.accentColor.opacity(0.75), radius: 4)
                }
            }
            .frame(width: 30, height: baseH)

            Spacer(minLength: 0)
                .frame(width: max(baseW - 10, 126))

            // Right ear: compact tabular badge count.
            ZStack {
                if let badge = primary?.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(resolved.accentColor.opacity(0.85), in: Capsule())
                } else {
                    Text("\(indicators.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 30, height: baseH)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let primary {
                onAmbientAction(primary)
            }
        }
        .help(indicators.map(\.title).joined(separator: ", "))
    }

    /// Deep obsidian shell whose top edge melts seamlessly into the hardware notch bezel,
    /// accented only along the lower perimeter by an ultra-subtle fading specular rim.
    @ViewBuilder
    private func notchShell(topRadius: CGFloat, bottomRadius: CGFloat) -> some View {
        if geometry.isPhysicalNotch {
            ZStack {
                NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(Color.black)

                // Subtle bottom-only glass sheen (zero white line along the top bezel seam).
                NotchBottomRimShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.08), .white.opacity(0.16), .white.opacity(0.08), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.65
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.20), .white.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        }
    }
}
