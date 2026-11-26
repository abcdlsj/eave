import SwiftUI

/// Single source of truth for Notch surface dimensions & corner geometry across all states,
/// keeping `NotchContainerView` morphing and `NotchPanelController` hit-testing mathematically locked.
struct NotchSurfaceMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOpacity: Double
    let isVisible: Bool

    static func resolve(for state: NotchState, geometry: NotchGeometry) -> NotchSurfaceMetrics {
        let baseW = geometry.notchRect.width
        let baseH = geometry.notchRect.height

        switch state {
        case .idle:
            return NotchSurfaceMetrics(
                width: baseW,
                height: baseH,
                topRadius: 8,
                bottomRadius: 11,
                shadowRadius: 0,
                shadowOpacity: 0,
                isVisible: false
            )
        case .ambient:
            return NotchSurfaceMetrics(
                width: baseW + 64,
                height: baseH,
                topRadius: 8,
                bottomRadius: 12,
                shadowRadius: 4,
                shadowOpacity: 0.14,
                isVisible: true
            )
        case .peek:
            return NotchSurfaceMetrics(
                width: baseW + 92,
                height: baseH,
                topRadius: 9,
                bottomRadius: 13.5,
                shadowRadius: 6,
                shadowOpacity: 0.18,
                isVisible: true
            )
        }
    }
}

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
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + topR * 0.68, y: rect.minY),
            control2: CGPoint(x: rect.minX + topR, y: rect.minY + topR * 0.32)
        )
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
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - topR, y: rect.minY + topR * 0.32),
            control2: CGPoint(x: rect.maxX - topR * 0.68, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Open-top perimeter path used to render a whisper-thin neutral titanium rim along the sides
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
    init(eaveHex hex: String?, fallback: Color = Color.white.opacity(0.85)) {
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
    @Environment(\.eaveHairline) private var hairline
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var strokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.22), Color.white.opacity(0.06)]
        }
        return [Color.black.opacity(0.11), Color.black.opacity(0.05)]
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background(
                    shape.fill(colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.45))
                )
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: strokeColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: hairline
                        )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: shape
                )
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: strokeColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: hairline
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
