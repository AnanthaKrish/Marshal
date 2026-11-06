import SwiftUI

/// The classic "extended notch" silhouette: the top corners flare outward so
/// the black melts into the menu bar, and the bottom corners are rounded.
struct NotchShape: Shape {
    static let collapsedFlare: CGFloat = 8
    static let expandedFlare: CGFloat = 12

    var flare: CGFloat
    var bottomRadius: CGFloat
    /// The rim stays open across the camera housing and menu bar.
    var closesTop = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.width / 4)
        let r = min(bottomRadius, (rect.width - 2 * f) / 2, rect.height - f)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-left flare (concave)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f, y: rect.minY + f),
            control: CGPoint(x: rect.minX + f, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f + r, y: rect.maxY),
            control: CGPoint(x: rect.minX + f, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - f, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX - f, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        // Top-right flare (concave)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - f, y: rect.minY)
        )
        if closesTop { path.closeSubpath() }
        return path
    }
}
