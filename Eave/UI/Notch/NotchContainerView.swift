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
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: stateMachine.state)
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
                .background(notchShell(topRadius: 8, bottomRadius: 12))
                .transition(.opacity)

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
                width: expanded ? max(baseW + 150, 336) : baseW + 104,
                alignment: .top
            )
            .background(notchShell(topRadius: expanded ? 12 : 9, bottomRadius: expanded ? 18 : 13))
            .shadow(color: .black.opacity(expanded ? 0.34 : 0.16), radius: expanded ? 14 : 6, y: expanded ? 6 : 2)

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
            .background(notchShell(topRadius: 14, bottomRadius: 22))
            .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
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
            Circle()
                .fill(resolved.accentColor)
                .frame(width: 5.5, height: 5.5)
                .frame(width: 22, height: baseH)

            Spacer(minLength: 0)
                .frame(width: max(baseW - 8, 124))

            Text(primary?.badge ?? "\(indicators.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22, height: baseH)
        }
        .padding(.horizontal, 6)
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
