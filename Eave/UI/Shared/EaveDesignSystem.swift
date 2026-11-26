import AppKit
import CoreText
import SwiftUI

// MARK: - Bundled Display Typography (Fredoka)

enum EaveTypography {
    private static let isFredokaLoaded: Bool = {
        let url = Bundle.main.url(forResource: "Fredoka", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "Fredoka", withExtension: "ttf")
        guard let url else { return false }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return NSFont(name: "Fredoka-SemiBold", size: 12) != nil
    }()

    /// Soft geometric rounded numeral font (Fredoka) for Notch & Second-Row badge counters.
    static func badgeFont(size: CGFloat, weight: String = "Fredoka-Regular") -> Font {
        if isFredokaLoaded, NSFont(name: weight, size: size) != nil {
            return .custom(weight, size: size)
        }
        return .system(size: size, weight: weight.contains("Regular") ? .regular : .semibold, design: .rounded)
    }
}

// MARK: - Appearance Mapping

extension AppAppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

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
    /// Restrained, tactile macOS Dock lift & neighbor wave spring.
    static let dockWave = Animation.spring(response: 0.24, dampingFraction: 0.72)
    /// Smooth settings tab transition.
    static let tabSwitch = Animation.spring(response: 0.26, dampingFraction: 0.88)
}

/// Subtle macOS Dock-style proximity magnification curve for icon shelves.
struct EaveDockMagnification: Equatable, Sendable {
    let scale: CGFloat
    let liftY: CGFloat
    let isPrimary: Bool

    static let resting = EaveDockMagnification(scale: 1.0, liftY: 0.0, isPrimary: false)

    /// When `reduceMotion` is true the hovered tile is still flagged as primary (for highlight), but never scales or lifts.
    static func resolve(index: Int, hoveredIndex: Int?, reduceMotion: Bool = false) -> EaveDockMagnification {
        guard let hoveredIndex else { return .resting }
        let distance = abs(index - hoveredIndex)
        if reduceMotion {
            return EaveDockMagnification(scale: 1.0, liftY: 0.0, isPrimary: distance == 0)
        }
        switch distance {
        case 0:
            return EaveDockMagnification(scale: 1.11, liftY: -1.5, isPrimary: true)
        case 1:
            return EaveDockMagnification(scale: 1.03, liftY: -0.5, isPrimary: false)
        default:
            return .resting
        }
    }
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

// MARK: - Adaptive Light / Dark Surface Palette

enum EavePalette {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.086, green: 0.088, blue: 0.096)
            : Color(red: 0.962, green: 0.964, blue: 0.972)
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.068, green: 0.070, blue: 0.078)
            : Color(red: 0.935, green: 0.938, blue: 0.948)
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.044)
            : Color.white.opacity(0.92)
    }

    static func cardBorder(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        if contrast == .increased {
            return scheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.22)
        }
        return scheme == .dark
            ? Color.white.opacity(0.085)
            : Color.black.opacity(0.075)
    }

    static func insetFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.24)
            : Color.black.opacity(0.030)
    }

    static func insetBorder(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        if contrast == .increased {
            return scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
        }
        return scheme == .dark
            ? Color.white.opacity(0.065)
            : Color.black.opacity(0.060)
    }

    static func divider(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        if contrast == .increased {
            return scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
        }
        return scheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.065)
    }

    static func pillFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.075)
            : Color.black.opacity(0.055)
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
        .accessibilityLabel(helpText)
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
            return Color(red: 0.11, green: 0.115, blue: 0.125).opacity(isHovered ? 0.88 : 1.0)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                radius: isHovered ? 4 : 2,
                y: 1
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.40)
            .animation(EaveMotion.pressSpring, value: configuration.isPressed)
            .animation(EaveMotion.hover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Understated hairline-bordered neutral secondary button.
struct EaveSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        EaveSecondaryButtonBody(configuration: configuration, compact: compact)
    }
}

private struct EaveSecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let compact: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var strokeOpacity: Double {
        if contrast == .increased { return isHovered ? 0.36 : 0.28 }
        return isHovered ? 0.16 : 0.095
    }

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(.primary.opacity(isEnabled ? (isHovered ? 1.0 : 0.82) : 0.35))
            .padding(.horizontal, compact ? 9 : 11.5)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 7.5, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.10 : 0.055)
                            : Color.black.opacity(isHovered ? 0.065 : 0.032)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 7.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 0.65)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(EaveMotion.pressSpring, value: configuration.isPressed)
            .animation(EaveMotion.hover, value: isHovered)
            .onHover { isHovered = $0 }
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let isIncreased = contrast == .increased
        Text(label)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(isDarkSurface ? Color.white.opacity(isIncreased ? 0.92 : 0.76) : Color.primary.opacity(isIncreased ? 0.90 : 0.72))
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
                        isDarkSurface
                            ? Color.white.opacity(isIncreased ? 0.32 : 0.14)
                            : Color.primary.opacity(isIncreased ? 0.30 : 0.12),
                        lineWidth: 0.55
                    )
            )
    }
}

// MARK: - Editorial Settings Card & Nested Sub-Settings Primitives

struct EaveSettingsCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

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
                            .foregroundStyle(contrast == .increased ? .secondary : .tertiary)
                    }
                }
                .padding(.horizontal, 3)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(EavePalette.cardFill(colorScheme))
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.0 : 0.035),
                        radius: 2.5,
                        y: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(EavePalette.cardBorder(colorScheme, contrast: contrast), lineWidth: 0.65)
            )
        }
    }
}

/// Recessed nested container for secondary / dependent settings beneath a parent toggle,
/// giving unmistakable visual hierarchy without noisy flat dividers.
struct EaveSettingsSubSection<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(EavePalette.insetFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .strokeBorder(EavePalette.insetBorder(colorScheme, contrast: contrast), lineWidth: 0.6)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
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

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Precision slider row with aligned label, optional caption, and monospaced value badge.
struct EaveSettingsSliderRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    var inset: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        inset: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.inset = inset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: inset ? 12.5 : 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(inset ? 0.90 : 1.0))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(valueText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(EavePalette.pillFill(colorScheme))
                    )
            }

            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(valueText)
            .controlSize(.small)
            // The only haptic in Eave: a light detent tick as the slider snaps to each step.
            .onChange(of: value) { oldValue, newValue in
                if oldValue != newValue { EaveHaptics.tick() }
            }
        }
        .padding(.horizontal, inset ? 12 : 14)
        .padding(.vertical, inset ? 9.5 : 10.5)
    }
}

/// Clean segmented control row with uniform padding for both primary and nested secondary settings.
struct EaveSettingsSegmentedRow<Selection: Hashable, OptionView: View>: View {
    let title: String
    let subtitle: String?
    @Binding var selection: Selection
    let pickerWidth: CGFloat
    var inset: Bool = false
    @ViewBuilder let options: () -> OptionView

    init(
        _ title: String,
        subtitle: String? = nil,
        selection: Binding<Selection>,
        pickerWidth: CGFloat = 190,
        inset: Bool = false,
        @ViewBuilder options: @escaping () -> OptionView
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.pickerWidth = pickerWidth
        self.inset = inset
        self.options = options
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: inset ? 12.5 : 13, weight: inset ? .medium : .regular))
                    .foregroundStyle(.primary.opacity(inset ? 0.90 : 1.0))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            Picker(title, selection: $selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(inset ? .small : .regular)
            .frame(width: pickerWidth)
        }
        .padding(.horizontal, inset ? 12 : 14)
        .padding(.vertical, inset ? 9.5 : 11)
    }
}

struct EaveCardDivider: View {
    var leadingInset: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(EavePalette.divider(colorScheme, contrast: contrast))
            .frame(height: 0.65)
            .padding(.leading, leadingInset)
    }
}

struct EavePageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.3)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}
