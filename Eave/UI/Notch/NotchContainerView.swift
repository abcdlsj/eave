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
                    triggerRimSweep(accentHex: alert.accentHex, source: alert.source)
                } else if case .ambient(let indicators) = newState, let primary = indicators.last, primary.loop {
                    triggerRimSweep(accentHex: primary.accentHex, source: primary.source)
                }
            }
            .task(id: rimLoopIdentity) {
                guard let config = activeLoopedRimConfig else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    guard !Task.isCancelled else { break }
                    triggerRimSweep(accentHex: config.accentHex, source: config.source)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var activeLoopedRimConfig: (accentHex: String?, source: NotchAlertSource)? {
        switch stateMachine.state {
        case .peek(let alert) where alert.loop:
            return (alert.accentHex, alert.source)
        case .ambient(let indicators):
            if let primary = indicators.last, primary.loop {
                return (primary.accentHex, primary.source)
            }
            return nil
        default:
            return nil
        }
    }

    private var rimLoopIdentity: String {
        switch stateMachine.state {
        case .peek(let alert) where alert.loop:
            return "peek.\(alert.id).\(alert.timestamp.timeIntervalSince1970)"
        case .ambient(let indicators):
            if let primary = indicators.last, primary.loop {
                return "ambient.\(primary.id).\(primary.accentHex ?? "")"
            }
            return "none"
        default:
            return "none"
        }
    }

    /// Fires a restrained 0.72s accent light sweep along the lower notch perimeter.
    private func triggerRimSweep(accentHex: String?, source: NotchAlertSource) {
        if let hex = accentHex, !hex.isEmpty {
            rimSweepColor = Color(eaveHex: hex)
        } else if source == .dockBadge {
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
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0

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
        .task(id: "\(primary?.id ?? "")-\(primary?.loop ?? false)-\(primary?.style.rawValue ?? "")") {
            guard let primary, primary.loop, primary.badge == nil, primary.style == .dot else { return }
            while !Task.isCancelled {
                rippleScale = 1.0
                rippleOpacity = 0.60
                withAnimation(.easeOut(duration: 0.72)) {
                    rippleScale = 2.4
                    rippleOpacity = 0.0
                }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
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
            let fontSize: CGFloat = badge.count <= 2 ? 12.0 : 10.5
            let isAccented = primary?.accentHex != nil || primary?.source == .dockBadge
            Text(badge)
                .font(EaveTypography.badgeFont(size: fontSize, weight: "Fredoka-Regular"))
                .tracking(0.2)
                .contentTransition(.numericText())
                .foregroundStyle(isAccented ? accentColor : .white.opacity(isHovered ? 0.96 : 0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else if primary?.style == .wave {
            NotchWaveBarsView(color: accentColor)
                .scaleEffect(isHovered ? 1.12 : 1.0)
        } else {
            // No badge provided -> quiet breathing accent dot (plus optional looped sonar ping).
            ZStack {
                if rippleOpacity > 0.01 {
                    Circle()
                        .stroke(accentColor.opacity(rippleOpacity), lineWidth: 0.95)
                        .frame(width: 5.5, height: 5.5)
                        .scaleEffect(rippleScale)
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: 5.5, height: 5.5)
                    .shadow(color: accentColor.opacity(breathe ? 0.45 : 0.12), radius: breathe ? 3 : 1)
                    .opacity(breathe ? 1.0 : 0.62)
                    .scaleEffect(isHovered ? 1.18 : 1.0)
            }
        }
    }
}
