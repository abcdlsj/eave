import SwiftUI

/// Root SwiftUI surface hosted inside the NotchPanel, morphing cleanly across all 4 NotchState cases.
struct NotchContainerView: View {
    let stateMachine: NotchStateMachine
    let geometryProvider: () -> NotchGeometry
    let capturedItemsProvider: () -> [CapturedMenuBarItem]
    let isScanningProvider: () -> Bool

    let onSelectBarItem: (MenuBarItemInfo) -> Void
    let onRefreshBar: () -> Void
    let onOpenSearch: () -> Void
    let onAlertAction: (NotchAlert) -> Void
    let onAmbientAction: (AmbientIndicator) -> Void

    private var geometry: NotchGeometry { geometryProvider() }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: stateMachine.state)
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
            // Collapsed completely flush behind the physical notch.
            Color.clear
                .frame(width: baseW, height: 1)

        case .ambient(let indicators):
            ambientView(indicators: indicators, baseW: baseW, baseH: baseH)
                .background(shellBackground(topRadius: 8, bottomRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))

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
                width: expanded ? max(baseW + 170, 360) : baseW + 128,
                alignment: .top
            )
            .background(shellBackground(topRadius: expanded ? 12 : 10, bottomRadius: expanded ? 20 : 14))
            .shadow(color: .black.opacity(expanded ? 0.36 : 0.2), radius: expanded ? 18 : 8, y: 6)

        case .bar:
            NotchBarView(
                items: capturedItemsProvider(),
                isLoading: isScanningProvider(),
                notchHeight: baseH,
                onSelectItem: onSelectBarItem,
                onRefresh: onRefreshBar,
                onOpenSearch: onOpenSearch,
                onClose: { stateMachine.closeBar() }
            )
            .frame(width: 480, alignment: .top)
            .background(shellBackground(topRadius: 14, bottomRadius: 22))
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
        }
    }

    private func ambientView(indicators: [AmbientIndicator], baseW: CGFloat, baseH: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left ear shows a subtle single pulse dot for the highest-priority active indicator.
            HStack(spacing: 4) {
                if let first = indicators.first {
                    Circle()
                        .fill(Color(eaveHex: first.accentHex))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 28, height: baseH)

            Spacer()
                .frame(width: max(baseW - 14, 120))

            // Right ear shows count / badge pill.
            HStack(spacing: 3) {
                if let badge = indicators.first?.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("\(indicators.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 28, height: baseH)
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let first = indicators.first {
                onAmbientAction(first)
            }
        }
        .help(indicators.map(\.title).joined(separator: ", "))
    }

    @ViewBuilder
    private func shellBackground(topRadius: CGFloat, bottomRadius: CGFloat) -> some View {
        if geometry.isPhysicalNotch {
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(Color.black)
                .overlay(
                    NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                )
        }
    }
}
