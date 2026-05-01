import SwiftUI

/// The notch silhouette. Bottom corners curve outward (convex) into the
/// menu bar to mirror the physical notch's inner curves. Top corners
/// flare outward via concave-from-outside curves: the path extends past
/// the silhouette's vertical walls and meets the screen edge with a smooth
/// transition — same shape that joins the real MacBook notch's vertical
/// walls to the screen top.
struct IslandShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        // Decoupled so the curve can start bending earlier on the vertical
        // wall (verticalDrop) without growing too much horizontally
        // (horizontalExtend) — feels like a longer, gentler flare instead
        // of a tight quarter circle.
        let topVerticalDrop: CGFloat = 13
        let topHorizontalExtend: CGFloat = 10
        let bottomRadius: CGFloat = 14
        var p = Path()

        // Top edge — extends past the rect by `topHorizontalExtend` on
        // each side so the corners can flare outward into the menu bar.
        p.move(to: CGPoint(x: r.minX - topHorizontalExtend, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + topHorizontalExtend, y: r.minY))

        // Top-right outward flare. Control point at the rect corner
        // gives a clean concave-from-outside (convex-from-inside) curve.
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY + topVerticalDrop),
            control: CGPoint(x: r.maxX, y: r.minY)
        )

        // Right vertical wall down to the bottom-right curve.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))

        // Bottom-right convex.
        p.addArc(
            center: CGPoint(x: r.maxX - bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))

        // Bottom-left convex.
        p.addArc(
            center: CGPoint(x: r.minX + bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left vertical wall up to where the top-left flare begins.
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + topVerticalDrop))

        // Top-left outward flare: mirror of top-right.
        p.addQuadCurve(
            to: CGPoint(x: r.minX - topHorizontalExtend, y: r.minY),
            control: CGPoint(x: r.minX, y: r.minY)
        )

        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var s = self
        s.inset += amount
        return s
    }
}
