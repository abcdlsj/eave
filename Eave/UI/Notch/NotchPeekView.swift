import AppKit
import SwiftUI

/// Ultra-minimalist notification peek hugging the physical MacBook notch.
/// Zero visual clutter: crisp app icon on left wing, whisper-clean indicator on right wing,
/// and a slim single-row quick-open sheet on hover.
struct NotchPeekView: View {
    let alert: NotchAlert
    let expanded: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(
            bundleIdentifier: alert.bundleIdentifier,
            fallbackSymbol: alert.symbolName,
            fallbackAccentHex: alert.accentHex
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Minimalist compact ears tightly flanking the physical camera housing.
            HStack(spacing: 0) {
                leftWing
                    .frame(width: 44, height: notchHeight)

                Spacer(minLength: 0)
                    .frame(width: max(notchWidth - 8, 124))

                rightWing
                    .frame(width: 44, height: notchHeight)
            }
            .padding(.horizontal, 8)

            if expanded {
                expandedRow
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryAction()
        }
    }

    private var leftWing: some View {
        renderIcon(size: 16, symbolSize: 12)
    }

    private var rightWing: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(resolved.accentColor)
                .frame(width: 5.5, height: 5.5)

            if let badge = alert.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
            }
        }
    }

    private var expandedRow: some View {
        HStack(spacing: 11) {
            renderIcon(size: 26, symbolSize: 15)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(alert.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                if let subtitle = alert.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if alert.bundleIdentifier != nil || alert.targetURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.top, 5)
        .padding(.bottom, 13)
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
            Image(systemName: resolved.symbolName ?? "bell.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(resolved.accentColor)
                .frame(width: size, height: size)
        }
    }
}
