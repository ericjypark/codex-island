import SwiftUI

/// The notch silhouette: flat top (sits flush with the screen edge) and
/// rounded bottom corners that mirror the physical notch's inner curves.
///
/// Uses `.continuous` (squircle) corners — curvature ramps in gradually
/// instead of jumping to a constant radius, matching how Apple draws the
/// hardware notch and the Dynamic Island. Plain circular arcs at this
/// scale show a visible kink at the tangent point.
struct IslandShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius: CGFloat = 14

        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            return UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: radius,
                    bottomTrailing: radius,
                    topTrailing: 0
                ),
                style: .continuous
            ).path(in: r)
        }
        #endif

        // Fallback for Ventura / Swift < 5.9
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius),
                    radius: radius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius),
                    radius: radius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var s = self
        s.inset += amount
        return s
    }
}
