import SwiftUI

/// Root SwiftUI surface hosted inside NotchPanel.
/// Uses ONE persistent pure-black obsidian shell whose geometry and corner curves continuously morph
/// with liquid-spring physics across `idle`, `ambient`, and `peek` — zero neon rims, pure hardware cohesion.
struct NotchContainerView: View {
    let stateMachine: NotchStateMachine
    let geometryProvider: () -> NotchGeometry
    let onAlertAction: (NotchAlert) -> Void
    let onAmbientAction: (AmbientIndicator) -> Void

    private var geometry: NotchGeometry { geometryProvider() }

    private var metrics: NotchSurfaceMetrics {
        NotchSurfaceMetrics.resolve(for: stateMachine.state, geometry: geometry)
    }

    private var stateAnimation: Animation {
        if case .idle = stateMachine.state {
            return EaveMotion.notchRetract
        }
        return EaveMotion.notchMorph
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Single persistent pure-black hardware shell (shadow strictly on static shell for 120fps).
                notchShell(metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)

                // State content clipped cleanly inside the morphing silhouette.
                stateContent
                    .frame(width: metrics.width, height: metrics.height, alignment: .top)
                    .clipShape(shellClipShape(metrics: metrics))
            }
            .opacity(metrics.isVisible ? 1 : 0)
            .allowsHitTesting(metrics.isVisible)
            .animation(stateAnimation, value: stateMachine.state)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var stateContent: some View {
        let baseW = geometry.notchRect.width
        let baseH = geometry.notchRect.height

        switch stateMachine.state {
        case .idle:
            Color.clear

        case .ambient(let indicators):
            NotchAmbientWingsView(
                indicators: indicators,
                notchWidth: baseW,
                notchHeight: baseH,
                onTap: { indicator in
                    EaveHaptics.tick()
                    onAmbientAction(indicator)
                }
            )
            .transition(.opacity)

        case .peek(let alert, let expanded):
            NotchPeekView(
                alert: alert,
                expanded: expanded,
                notchWidth: baseW,
                notchHeight: baseH,
                onPrimaryAction: {
                    EaveHaptics.tick()
                    onAlertAction(alert)
                },
                onDismiss: {
                    EaveHaptics.tick()
                    stateMachine.dismissPeek()
                }
            )
            .transition(.opacity)
        }
    }

    private func shellClipShape(metrics: NotchSurfaceMetrics) -> AnyShape {
        if geometry.isPhysicalNotch {
            AnyShape(NotchShape(topCornerRadius: metrics.topRadius, bottomCornerRadius: metrics.bottomRadius))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: metrics.bottomRadius, style: .continuous))
        }
    }

    /// Pure optical `#000000` obsidian shell whose top edge disappears seamlessly into the MacBook bezel,
    /// finished only by a razor-thin neutral titanium rim along the lower perimeter.
    @ViewBuilder
    private func notchShell(metrics: NotchSurfaceMetrics) -> some View {
        if geometry.isPhysicalNotch {
            ZStack {
                NotchShape(topCornerRadius: metrics.topRadius, bottomCornerRadius: metrics.bottomRadius)
                    .fill(Color.black)
                    .shadow(
                        color: .black.opacity(metrics.shadowOpacity),
                        radius: metrics.shadowRadius,
                        y: metrics.shadowRadius > 0 ? 6 : 0
                    )

                NotchBottomRimShape(topCornerRadius: metrics.topRadius, bottomCornerRadius: metrics.bottomRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.06), .white.opacity(0.11), .white.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.6
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: metrics.bottomRadius, style: .continuous)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.045).opacity(0.96))
                .shadow(
                    color: .black.opacity(metrics.shadowOpacity),
                    radius: metrics.shadowRadius,
                    y: metrics.shadowRadius > 0 ? 6 : 0
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.bottomRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                )
        }
    }
}

// MARK: - Quiet Architectural Ambient Wings

private struct NotchAmbientWingsView: View {
    let indicators: [AmbientIndicator]
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: (AmbientIndicator) -> Void

    @State private var isHovered = false
    @State private var breathe = false

    private var primary: AmbientIndicator? { indicators.first }

    /// Crisp restrained status color: Apple notification crimson for Dock badges, warm silver for ambient signals.
    private var dotColor: Color {
        if primary?.source == .dockBadge {
            return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
        return Color.white.opacity(0.86)
    }

    var body: some View {
        Button {
            if let primary { onTap(primary) }
        } label: {
            HStack(spacing: 0) {
                // Left wing: quiet precision LED dot (no loud neon halo).
                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)
                    .opacity(breathe ? 1.0 : 0.58)
                    .frame(width: 24, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 6, 124))

                // Right wing: whisper-clean tabular count.
                Text(primary?.badge ?? "\(indicators.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(isHovered ? 0.96 : 0.72))
                    .frame(width: 24, height: notchHeight)
            }
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.97, pressedOpacity: 0.90))
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                isHovered = hovering
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .help(indicators.map(\.title).joined(separator: ", "))
    }
}
