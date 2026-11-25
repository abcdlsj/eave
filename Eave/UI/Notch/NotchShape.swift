import SwiftUI

/// Continuous morphing silhouette matching Apple's physical MacBook notch with concave top shoulders
/// and smooth rounded bottom corners.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width * 0.25, rect.height * 0.5)
        let botR = min(bottomCornerRadius, rect.width * 0.45, rect.height * 0.5)

        var path = Path()
        // Outer top-left flare curving smoothly inward into the notch body.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )
        // Left vertical edge down to bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )
        // Bottom edge across to bottom-right corner.
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )
        // Right vertical edge up to outer top-right flare.
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Shared color and Tahoe Liquid Glass / Sequoia Material helpers.
extension Color {
    init(eaveHex hex: String?, fallback: Color = Color(red: 0.22, green: 0.74, blue: 0.97)) {
        guard let hex else {
            self = fallback
            return
        }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = fallback
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

struct EaveGlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                )
        }
    }
}

extension View {
    func eaveGlassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(EaveGlassBackgroundModifier(cornerRadius: cornerRadius))
    }
}
