import AppKit
import SwiftUI

/// Dynamic Island–grade notification peek flanking the physical camera housing,
/// expanding smoothly into a luminous quick-action card on hover.
struct NotchPeekView: View {
    let alert: NotchAlert
    let expanded: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    @State private var pulse = false
    @State private var isOpenHovered = false

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(
            bundleIdentifier: alert.bundleIdentifier,
            fallbackSymbol: alert.symbolName,
            fallbackAccentHex: alert.accentHex
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Flanking wing row aligned optically with the hardware camera notch.
            HStack(spacing: 0) {
                leftWing
                    .frame(width: 54, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 10, 128))

                rightWing
                    .frame(width: 54, height: notchHeight)
            }
            .padding(.horizontal, 12)

            if expanded {
                expandedCard
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryAction()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Compact Flanking Wings

    private var leftWing: some View {
        ZStack {
            // Subtle color aura behind the peeking app icon.
            Circle()
                .fill(resolved.accentColor.opacity(0.28))
                .frame(width: 24, height: 24)
                .blur(radius: 6)

            renderIcon(size: 19, symbolSize: 13)
        }
    }

    private var rightWing: some View {
        HStack {
            Spacer(minLength: 0)
            if let badge = alert.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [resolved.accentColor, resolved.accentColor.opacity(0.78)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: resolved.accentColor.opacity(0.45), radius: 5, y: 1)
                    )
                    .lineLimit(1)
            } else {
                ZStack {
                    Circle()
                        .fill(resolved.accentColor.opacity(pulse ? 0.35 : 0.12))
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(resolved.accentColor)
                        .frame(width: 7, height: 7)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Expanded Action Card

    private var expandedCard: some View {
        HStack(spacing: 14) {
            // App icon resting on a soft ambient color halo.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(resolved.accentColor.opacity(0.26))
                    .frame(width: 40, height: 40)
                    .blur(radius: 10)

                renderIcon(size: 38, symbolSize: 20)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let badge = alert.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(resolved.accentColor.opacity(0.9), in: Capsule())
                    }
                }

                if let subtitle = alert.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                if alert.bundleIdentifier != nil || alert.targetURL != nil {
                    Button {
                        onPrimaryAction()
                    } label: {
                        Text("Open")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(isOpenHovered ? 1.0 : 0.92))
                            )
                            .scaleEffect(isOpenHovered ? 1.04 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { isOpenHovered = $0 }
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func renderIcon(size: CGFloat, symbolSize: CGFloat) -> some View {
        if let nsImage = resolved.image {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [resolved.accentColor.opacity(0.32), resolved.accentColor.opacity(0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(resolved.accentColor.opacity(0.35), lineWidth: 0.6)
                    )
                Image(systemName: resolved.symbolName ?? "bell.badge.fill")
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(resolved.accentColor)
            }
            .frame(width: size, height: size)
        }
    }
}
