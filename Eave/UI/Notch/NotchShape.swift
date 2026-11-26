import SwiftUI

/// Single source of truth for Notch surface dimensions & corner geometry across all four states,
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
                width: baseW + 58,
                height: baseH,
                topRadius: 8,
                bottomRadius: 12,
                shadowRadius: 4,
                shadowOpacity: 0.14,
                isVisible: true
            )
        case .peek(_, let expanded):
            if expanded {
                return NotchSurfaceMetrics(
                    width: max(baseW + 172, 368),
                    height: baseH + 66,
                    topRadius: 12,
                    bottomRadius: 20,
                    shadowRadius: 16,
                    shadowOpacity: 0.34,
                    isVisible: true
                )
            } else {
                return NotchSurfaceMetrics(
                    width: baseW + 106,
                    height: baseH,
                    topRadius: 9,
                    bottomRadius: 13.5,
                    shadowRadius: 6,
                    shadowOpacity: 0.18,
                    isVisible: true
                )
            }
        case .bar:
            return NotchSurfaceMetrics(
                width: 536,
                height: max(baseH, 36) + 98,
                topRadius: 14,
                bottomRadius: 23,
                shadowRadius: 20,
                shadowOpacity: 0.38,
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
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.65
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
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.65
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
