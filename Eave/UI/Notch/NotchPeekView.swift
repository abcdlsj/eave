import AppKit
import SwiftUI

/// Renders a hidden-app notification peeking from the notch wings, expanding into a quick-action card on hover.
struct NotchPeekView: View {
    let alert: NotchAlert
    let expanded: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    private var accentColor: Color {
        Color(eaveHex: alert.accentHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top wing row flanking the physical camera housing.
            HStack(spacing: 0) {
                leftWing
                    .frame(width: 56, height: notchHeight)

                Spacer()
                    .frame(width: max(notchWidth - 16, 120))

                rightWing
                    .frame(width: 56, height: notchHeight)
            }
            .padding(.horizontal, 10)

            if expanded {
                expandedCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryAction()
        }
    }

    private var leftWing: some View {
        HStack {
            Spacer(minLength: 0)
            alertIcon
                .frame(width: 18, height: 18)
            Spacer(minLength: 0)
        }
    }

    private var rightWing: some View {
        HStack {
            Spacer(minLength: 0)
            if let badge = alert.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentColor, in: Capsule())
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
    }

    private var expandedCard: some View {
        HStack(spacing: 12) {
            alertIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = alert.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if alert.bundleIdentifier != nil || alert.targetURL != nil {
                    Button("Open") {
                        onPrimaryAction()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var alertIcon: some View {
        if let bundleID = alert.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: alert.symbolName ?? "bell.badge.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }
}
