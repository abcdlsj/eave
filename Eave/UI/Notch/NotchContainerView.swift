import SwiftUI

/// Root SwiftUI surface hosted inside NotchPanel.
/// Uses ONE persistent pure-black obsidian shell whose geometry and corner curves continuously morph
/// with liquid-spring physics across `idle`, `ambient`, and `peek` — strictly single-line hardware height.
struct NotchContainerView: View {
    let stateMachine: NotchStateMachine
    let geometryProvider: () -> NotchGeometry
    let onAlertAction: (NotchAlert) -> Void
    let onAmbientAction: (AmbientIndicator) -> Void

    @State private var rimSweepProgress: CGFloat = 0
    @State private var rimSweepOpacity: Double = 0
    @State private var rimSweepColor: Color = .white

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
                notchShell(metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)

                stateContent
                    .frame(width: metrics.width, height: metrics.height, alignment: .top)
                    .clipShape(shellClipShape(metrics: metrics))
            }
            .opacity(metrics.isVisible ? 1 : 0)
            .allowsHitTesting(metrics.isVisible)
            .animation(stateAnimation, value: stateMachine.state)
            .onChange(of: stateMachine.state) { _, newState in
                if case .peek(let alert) = newState {
                    triggerRimSweep(for: alert)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Fires a single restrained 0.72s accent light sweep along the lower notch perimeter on peek arrival.
    private func triggerRimSweep(for alert: NotchAlert) {
        if let hex = alert.accentHex, !hex.isEmpty {
            rimSweepColor = Color(eaveHex: hex)
        } else if alert.source == .dockBadge {
            rimSweepColor = Color(red: 1.0, green: 0.27, blue: 0.23)
        } else {
            rimSweepColor = Color.white.opacity(0.85)
        }

        rimSweepProgress = 0.0
        rimSweepOpacity = 0.85
        withAnimation(.easeOut(duration: 0.72)) {
            rimSweepProgress = 1.25
        }
        withAnimation(.easeIn(duration: 0.34).delay(0.40)) {
            rimSweepOpacity = 0.0
        }
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

        case .peek(let alert):
            NotchPeekView(
                alert: alert,
                notchWidth: baseW,
                notchHeight: baseH,
                onPrimaryAction: {
                    EaveHaptics.tick()
                    onAlertAction(alert)
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

    /// Pure optical `#000000` obsidian shell whose top edge disappears seamlessly into the MacBook bezel.
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

                // One-shot arrival accent shimmer along the bottom rim (zero cost at rest).
                if rimSweepOpacity > 0.01 {
                    NotchBottomRimShape(topCornerRadius: metrics.topRadius, bottomCornerRadius: metrics.bottomRadius)
                        .trim(
                            from: max(0, rimSweepProgress - 0.32),
                            to: min(1, rimSweepProgress)
                        )
                        .stroke(
                            rimSweepColor.opacity(rimSweepOpacity),
                            style: StrokeStyle(lineWidth: 1.15, lineCap: .round)
                        )
                        .shadow(color: rimSweepColor.opacity(rimSweepOpacity * 0.65), radius: 3)
                }
            }
        } else {
            ZStack {
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

                if rimSweepOpacity > 0.01 {
                    RoundedRectangle(cornerRadius: metrics.bottomRadius, style: .continuous)
                        .trim(
                            from: max(0, rimSweepProgress - 0.32),
                            to: min(1, rimSweepProgress)
                        )
                        .stroke(
                            rimSweepColor.opacity(rimSweepOpacity),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                        )
                }
            }
        }
    }
}

// MARK: - Quiet Architectural Ambient Wings (Icon + Accent Dot, Wave, or Optional Count)

private struct NotchAmbientWingsView: View {
    let indicators: [AmbientIndicator]
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onTap: (AmbientIndicator) -> Void

    @State private var isHovered = false
    @State private var breathe = false

    private var primary: AmbientIndicator? { indicators.last }

    private var resolvedIcon: AppIconService.ResolvedIcon? {
        guard let primary else { return nil }
        return AppIconService.shared.resolveNotchIcon(
            iconPath: primary.iconPath,
            symbolName: primary.symbolName,
            bundleIdentifier: primary.bundleIdentifier,
            accentHex: primary.accentHex
        )
    }

    private var accentColor: Color {
        if let hex = primary?.accentHex, !hex.isEmpty {
            return Color(eaveHex: hex)
        }
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
                leftWing
                    .frame(width: 26, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 4, 124))

                rightWing
                    .frame(width: 26, height: notchHeight)
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
    }

    @ViewBuilder
    private var leftWing: some View {
        if let icon = resolvedIcon {
            if let image = icon.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .opacity(isHovered ? 1.0 : 0.90)
            } else if let symbol = icon.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.98 : 0.80))
            }
        } else {
            Circle()
                .fill(accentColor)
                .frame(width: 5, height: 5)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let badge = primary?.badge, !badge.isEmpty {
            Text(badge)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(
                    (primary?.accentHex != nil || primary?.source == .dockBadge)
                        ? accentColor
                        : .white.opacity(isHovered ? 0.98 : 0.78)
                )
        } else if primary?.style == .wave {
            NotchWaveBarsView(color: accentColor)
                .scaleEffect(isHovered ? 1.12 : 1.0)
        } else {
            // No badge provided -> quiet breathing accent dot, never forces a number.
            Circle()
                .fill(accentColor)
                .frame(width: 5.5, height: 5.5)
                .shadow(color: accentColor.opacity(breathe ? 0.45 : 0.12), radius: breathe ? 3 : 1)
                .opacity(breathe ? 1.0 : 0.62)
                .scaleEffect(isHovered ? 1.18 : 1.0)
        }
    }
}
