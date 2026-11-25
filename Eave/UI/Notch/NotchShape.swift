import SwiftUI

/// Optically continuous MacBook notch silhouette with smooth concave top shoulders
/// (fusing seamlessly into the physical top bezel) and soft squircle-like bottom curves.
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
        let topR = min(topCornerRadius, rect.width * 0.22, rect.height * 0.48)
        let botR = min(bottomCornerRadius, (rect.width - topR * 2) * 0.45, rect.height * 0.55)

        var path = Path()
        // Outer top-left flare starting flush with the hardware display edge.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Smooth cubic concave shoulder curving down into the left vertical wall.
        path.addCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + topR * 0.68, y: rect.minY),
            control2: CGPoint(x: rect.minX + topR, y: rect.minY + topR * 0.32)
        )
        // Left vertical edge.
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        // Bottom-left continuous curve.
        path.addCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control1: CGPoint(x: rect.minX + topR, y: rect.maxY - botR * 0.32),
            control2: CGPoint(x: rect.minX + topR + botR * 0.32, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        // Bottom-right continuous curve.
        path.addCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control1: CGPoint(x: rect.maxX - topR - botR * 0.32, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR * 0.32)
        )
        // Right vertical edge.
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        // Smooth cubic concave shoulder flaring back out to top-right bezel.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - topR, y: rect.minY + topR * 0.32),
            control2: CGPoint(x: rect.maxX - topR * 0.68, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Open-top perimeter path used to render an ultra-subtle machined glass rim along the sides
/// and bottom of the notch while keeping the top edge 100% invisible against the hardware bezel.
struct NotchBottomRimShape: Shape {
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
        let topR = min(topCornerRadius, rect.width * 0.22, rect.height * 0.48)
        let botR = min(bottomCornerRadius, (rect.width - topR * 2) * 0.45, rect.height * 0.55)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY + topR))
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        path.addCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control1: CGPoint(x: rect.minX + topR, y: rect.maxY - botR * 0.32),
            control2: CGPoint(x: rect.minX + topR + botR * 0.32, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control1: CGPoint(x: rect.maxX - topR - botR * 0.32, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR * 0.32)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        return path
    }
}

/// Shared color and Tahoe Liquid Glass / Sequoia Material helpers.
extension Color {
    init(eaveHex hex: String?, fallback: Color = Color(red: 0.24, green: 0.72, blue: 0.98)) {
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
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        }
    }
}

extension View {
    func eaveGlassSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(EaveGlassBackgroundModifier(cornerRadius: cornerRadius))
    }
}
