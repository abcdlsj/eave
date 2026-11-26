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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .frame(width: 38, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 4, 124))

                rightSignalWing
                    .frame(width: 38, height: notchHeight)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.97, pressedOpacity: 0.90))
        .accessibilityLabel(
            NotchAccessibility.label(
                bundleIdentifier: alert.bundleIdentifier,
                source: alert.source,
                badge: alert.badge,
                isOngoing: false,
                style: alert.style
            )
        )
        .accessibilityHint(
            NotchAccessibility.hint(
                bundleIdentifier: alert.bundleIdentifier,
                source: alert.source,
                hasURL: alert.targetURL != nil
            )
        )
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
        .task(id: "\(alert.id)-\(alert.timestamp.timeIntervalSince1970)-\(alert.loop)") {
            guard !reduceMotion, alert.loop, alert.badge == nil, alert.style == .dot else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { break }
                triggerSonarPing()
            }
        }
    }

    private func triggerArrivalOptics() {
        guard !reduceMotion else {
            arrivalScale = 1.0
            return
        }
        // Crisp icon spring settle
        arrivalScale = 0.82
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
            arrivalScale = 1.0
        }

        // Single restrained sonar ping on dot-only arrivals
        guard alert.badge == nil, alert.style == .dot else { return }
        triggerSonarPing()
    }

    private func triggerSonarPing() {
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
        .scaleEffect(arrivalScale * (isHovered && !reduceMotion ? 1.08 : 1.0))
    }

    @ViewBuilder
    private var rightSignalWing: some View {
        if let badge = alert.badge, !badge.isEmpty {
            let fontSize: CGFloat = badge.count <= 2 ? 13.0 : 11.5
            let isAccented = alert.accentHex != nil || alert.source == .dockBadge
            Text(badge)
                .font(EaveTypography.badgeFont(size: fontSize, weight: "Fredoka-Regular"))
                .tracking(0.2)
                .contentTransition(.numericText())
                .foregroundStyle(isAccented ? accentColor : .white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else if alert.style == .wave {
            NotchWaveBarsView(color: accentColor)
                .scaleEffect(isHovered && !reduceMotion ? 1.12 : 1.0)
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
                    .scaleEffect(isHovered && !reduceMotion ? 1.18 : 1.0)
            }
        }
    }
}

/// Spoken VoiceOver descriptions for textless Notch wings.
@MainActor
enum NotchAccessibility {
    static func sourceName(bundleIdentifier: String?, source: NotchAlertSource) -> String {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url.deletingPathExtension().lastPathComponent
        }
        switch source {
        case .dockBadge, .menuBarAX: return "App"
        case .bridge: return "Script"
        case .system: return "Eave"
        }
    }

    static func label(
        bundleIdentifier: String?,
        source: NotchAlertSource,
        badge: String?,
        isOngoing: Bool,
        style: NotchSignalStyle
    ) -> String {
        let name = sourceName(bundleIdentifier: bundleIdentifier, source: source)
        if let badge, !badge.isEmpty {
            return "\(name) notification, \(badge) new"
        }
        if isOngoing {
            return style == .wave ? "\(name) activity in progress" : "\(name) ongoing signal"
        }
        return "\(name) notification"
    }

    static func hint(bundleIdentifier: String?, source: NotchAlertSource, hasURL: Bool) -> String {
        if hasURL { return "Opens the linked page." }
        if bundleIdentifier != nil {
            return "Opens \(sourceName(bundleIdentifier: bundleIdentifier, source: source))."
        }
        return "Dismisses the alert."
    }
}

/// Restrained 3-bar vertical activity indicator for active background work (AI agents, builds, syncs).
/// Used only when the sender explicitly requests `style=wave`.
struct NotchWaveBarsView: View {
    let color: Color
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Reduce Motion: keep the bars at a static resting height.
            if !reduceMotion { phase = true }
        }
    }
}
