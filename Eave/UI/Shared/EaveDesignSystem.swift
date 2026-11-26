import AppKit
import SwiftUI

// MARK: - Unified Motion Language

/// Curated spring and easing curves tuned for 120Hz ProMotion macOS displays.
enum EaveMotion {
    /// Organic liquid-obsidian expansion emerging from the physical MacBook notch.
    static let notchMorph = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.08)
    /// Taut, zero-wobble retraction back into the hardware bezel.
    static let notchRetract = Animation.spring(response: 0.26, dampingFraction: 0.90, blendDuration: 0.06)
    /// Crisp interactive spring for tiles, pills, and selection slides.
    static let microSpring = Animation.spring(response: 0.22, dampingFraction: 0.78)
    /// Instant tactile press-down and release bounce.
    static let pressSpring = Animation.spring(response: 0.15, dampingFraction: 0.72)
    /// Silky hover transitions without sluggishness.
    static let hover = Animation.easeOut(duration: 0.13)
    /// Smooth settings tab transition.
    static let tabSwitch = Animation.spring(response: 0.26, dampingFraction: 0.88)
}

// MARK: - Subtle Trackpad Haptics

@MainActor
enum EaveHaptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

// MARK: - Tactile Button Styles

/// Tactile press-scale button style for custom interactive surfaces (tiles, cards, rows).
struct EaveTactileButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95
    var pressedOpacity: Double = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(EaveMotion.pressSpring, value: configuration.isPressed)
    }
}

/// Whisper-quiet obsidian icon button for Notch surfaces.
/// Borderless at rest to avoid visual clutter; reveals a soft neutral halo on hover and crisp press-down.
struct EaveNotchIconButton: View {
    let symbol: String
    let helpText: String
    var size: CGFloat = 24
    var iconSize: CGFloat = 10.5
    var spinOnClick: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var spinCount: Int = 0

    var body: some View {
        Button {
            EaveHaptics.tick()
            if spinOnClick {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) {
                    spinCount += 1
                }
            }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white.opacity(isHovered ? 0.96 : 0.44))
                .rotationEffect(.degrees(Double(spinCount) * 360))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0.0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.86, pressedOpacity: 0.82))
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                isHovered = hovering
            }
        }
        .help(helpText)
    }
}

/// High-contrast architectural monochrome primary CTA button (Apple / Linear studio aesthetic).
struct EaveProminentButtonStyle: ButtonStyle {
    var isConfirmed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        EaveProminentButtonBody(configuration: configuration, isConfirmed: isConfirmed)
    }
}

private struct EaveProminentButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isConfirmed: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var fillColor: Color {
        if isConfirmed {
            return colorScheme == .dark
                ? Color(red: 0.22, green: 0.68, blue: 0.44)
                : Color(red: 0.14, green: 0.54, blue: 0.34)
        }
        if colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.98 : 0.90)
        } else {
            return Color(red: 0.11, green: 0.115, blue: 0.125).opacity(isHovered ? 0.90 : 1.0)
        }
    }

    private var labelColor: Color {
        if isConfirmed { return .white }
        return colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.0 : 0.12),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.10),
                radius: isHovered ? 4 : 2,
                y: 1
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.40)
            .animation(EaveMotion.pressSpring, value: configuration.isPressed)
            .animation(EaveMotion.hover, value: isHovered)
            .onHover { isHovered = $0 }
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { EaveHaptics.tick() }
            }
    }
}

/// Understated hairline-bordered neutral secondary button.
struct EaveSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EaveSecondaryButtonBody(configuration: configuration)
    }
}

private struct EaveSecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(isEnabled ? (isHovered ? 1.0 : 0.82) : 0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0.10), lineWidth: 0.65)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(EaveMotion.pressSpring, value: configuration.isPressed)
            .animation(EaveMotion.hover, value: isHovered)
            .onHover { isHovered = $0 }
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { EaveHaptics.tick() }
            }
    }
}

// MARK: - Tactile Physical Keycap

/// Minimalist macOS keyboard keycap with crisp hairline bevel.
struct EaveKeycap: View {
    let label: String
    var fontSize: CGFloat = 10.5
    var horizontalPadding: CGFloat = 5.5
    var verticalPadding: CGFloat = 2.5
    var isDarkSurface: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(isDarkSurface ? Color.white.opacity(0.76) : Color.primary.opacity(0.72))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: fontSize * 1.85)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isDarkSurface ? Color.white.opacity(0.09) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isDarkSurface ? Color.white.opacity(0.14) : Color.primary.opacity(0.12),
                        lineWidth: 0.55
                    )
            )
    }
}

// MARK: - Editorial Settings Card & Row Primitives

struct EaveSettingsCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.65)
            )
        }
    }
}

struct EaveSettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10.5)
    }
}

struct EaveCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.065))
            .frame(height: 0.65)
            .padding(.leading, 14)
    }
}

struct EavePageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
    }
}
