import AppKit
import SwiftUI

/// Pure single-line hardware-height notification wings flanking the MacBook notch.
/// Zero text sheets: displays only the sender's icon on the left wing and a custom-colored
/// accent dot (with a subtle one-shot sonar ping on arrival), optional 3-bar wave, or numeric badge on the right.
struct NotchPeekView: View {
    let alert: NotchAlert
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onPrimaryAction: () -> Void

    @State private var isHovered = false
    @State private var arrivalScale: CGFloat = 0.84
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolveNotchIcon(
            iconPath: alert.iconPath,
            symbolName: alert.symbolName,
            bundleIdentifier: alert.bundleIdentifier,
            accentHex: alert.accentHex
        )
    }

    private var accentColor: Color {
        if let hex = alert.accentHex, !hex.isEmpty {
            return Color(eaveHex: hex)
        }
        if alert.source == .dockBadge {
            return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
        return Color.white.opacity(0.88)
    }

    var body: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 0) {
                leftIconWing
                    .frame(width: 34, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 4, 124))

                rightSignalWing
                    .frame(width: 34, height: notchHeight)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.97, pressedOpacity: 0.90))
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                isHovered = hovering
            }
        }
        .onAppear {
            triggerArrivalOptics()
        }
        .onChange(of: alert.timestamp) { _, _ in
            triggerArrivalOptics()
        }
    }

    private func triggerArrivalOptics() {
        // Crisp icon spring settle
        arrivalScale = 0.82
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
            arrivalScale = 1.0
        }

        // Single restrained sonar ping on dot-only arrivals (never loops)
        guard alert.badge == nil, alert.style == .dot else { return }
        rippleScale = 1.0
        rippleOpacity = 0.68
        withAnimation(.easeOut(duration: 0.72)) {
            rippleScale = 2.5
            rippleOpacity = 0.0
        }
    }

    @ViewBuilder
    private var leftIconWing: some View {
        Group {
            if let nsImage = resolved.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: resolved.symbolName ?? "bell.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.90))
                    .frame(width: 17, height: 17)
            }
        }
        .id("\(alert.id)-\(alert.iconPath ?? "")-\(alert.symbolName ?? "")-\(alert.bundleIdentifier ?? "")")
        .transition(.opacity.combined(with: .scale(scale: 0.86)))
        .scaleEffect(arrivalScale * (isHovered ? 1.08 : 1.0))
    }

    @ViewBuilder
    private var rightSignalWing: some View {
        if let badge = alert.badge, !badge.isEmpty {
            Text(badge)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .padding(.horizontal, 5.5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(
                            (alert.accentHex != nil || alert.source == .dockBadge)
                                ? accentColor.opacity(0.92)
                                : Color.white.opacity(0.16)
                        )
                )
        } else if alert.style == .wave {
            NotchWaveBarsView(color: accentColor)
                .scaleEffect(isHovered ? 1.12 : 1.0)
        } else {
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(rippleOpacity), lineWidth: 1.0)
                    .frame(width: 6.5, height: 6.5)
                    .scaleEffect(rippleScale)

                Circle()
                    .fill(accentColor)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(color: accentColor.opacity(0.42), radius: 3)
                    .scaleEffect(isHovered ? 1.18 : 1.0)
            }
        }
    }
}

/// Restrained 3-bar vertical activity indicator for active background work (AI agents, builds, syncs).
/// Used only when the sender explicitly requests `style=wave`.
struct NotchWaveBarsView: View {
    let color: Color
    @State private var phase = false

    private let heights: [(CGFloat, CGFloat, Double)] = [
        (4.5, 10.5, 0.00),
        (11.0, 5.0, 0.16),
        (5.5, 9.5, 0.32)
    ]

    var body: some View {
        HStack(spacing: 2.2) {
            ForEach(0..<3, id: \.self) { idx in
                let spec = heights[idx]
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2.1, height: phase ? spec.1 : spec.0)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(spec.2),
                        value: phase
                    )
            }
        }
        .frame(height: 12, alignment: .center)
        .onAppear {
            phase = true
        }
    }
}
