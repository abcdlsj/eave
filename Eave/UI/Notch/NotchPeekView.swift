import AppKit
import SwiftUI

/// Refined Dynamic Island–inspired notification peek anchored seamlessly to the physical MacBook notch.
/// - Compact state: clean app icon on left wing, whisper-clean badge/dot on right wing.
/// - Expanded state (on hover): zero duplicate icons and zero clunky dividers — morphs into a serene,
///   single-hero obsidian notification sheet with matte neutral controls.
struct NotchPeekView: View {
    let alert: NotchAlert
    let expanded: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    @State private var isOpenHovered = false

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(
            bundleIdentifier: alert.bundleIdentifier,
            fallbackSymbol: alert.symbolName,
            fallbackAccentHex: alert.accentHex
        )
    }

    private var hasPrimaryTarget: Bool {
        alert.bundleIdentifier != nil || alert.targetURL != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                // Quiet top clearance flanking the physical camera housing (no duplicated app icon!).
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Spacer(minLength: 0)
                        .frame(width: max(notchWidth, 130))

                    HStack {
                        Spacer(minLength: 0)
                        EaveNotchIconButton(
                            symbol: "xmark",
                            helpText: "Dismiss",
                            size: 20,
                            iconSize: 8.5,
                            action: onDismiss
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 14)
                }
                .frame(height: notchHeight)

                expandedHeroRow
                    .transition(.opacity.combined(with: .offset(y: -4)))
            } else {
                compactWings
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryAction()
        }
    }

    // MARK: - Compact Wings (Flanking Physical Camera)

    private var compactWings: some View {
        HStack(spacing: 0) {
            // Left wing: crisp app icon floating cleanly in pure black.
            renderCompactIcon
                .frame(width: 44, height: notchHeight)

            Spacer(minLength: 0)
                .frame(width: max(notchWidth - 6, 124))

            // Right wing: clean restrained badge or single precision status dot.
            rightCompactWing
                .frame(width: 44, height: notchHeight)
        }
        .padding(.horizontal, 9)
    }

    @ViewBuilder
    private var rightCompactWing: some View {
        if let badge = alert.badge, !badge.isEmpty {
            Text(badge)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(
                            alert.source == .dockBadge
                                ? Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.92)
                                : Color.white.opacity(0.14)
                        )
                )
        } else {
            Circle()
                .fill(alert.source == .dockBadge ? Color(red: 1.0, green: 0.27, blue: 0.23) : Color.white.opacity(0.85))
                .frame(width: 5.5, height: 5.5)
        }
    }

    // MARK: - Expanded Hero Sheet (Apple Dynamic Island Craft)

    private var expandedHeroRow: some View {
        HStack(spacing: 12) {
            renderHeroIcon

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.15)
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)

                    if let badge = alert.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.11)))
                    }
                }

                if let subtitle = alert.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if hasPrimaryTarget {
                Button(action: onPrimaryAction) {
                    HStack(spacing: 3) {
                        Text("Open")
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(isOpenHovered ? 1.0 : 0.88))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isOpenHovered ? 0.20 : 0.12))
                    )
                }
                .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.93))
                .onHover { hovering in
                    withAnimation(EaveMotion.hover) {
                        isOpenHovered = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(height: 64)
    }

    // MARK: - Crisp Icon Rendering (Zero Neon Aura)

    @ViewBuilder
    private var renderCompactIcon: some View {
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
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 17, height: 17)
        }
    }

    @ViewBuilder
    private var renderHeroIcon: some View {
        if let nsImage = resolved.image {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 34, height: 34)
                Image(systemName: resolved.symbolName ?? "bell.fill")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
            }
        }
    }
}
