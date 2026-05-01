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
        let topRadius: CGFloat = 8
        let bottomRadius: CGFloat = 14
        var p = Path()

        // Top edge — extends past the rect's left/right by `topRadius` so
        // the corners can flare outward into the menu bar.
        p.move(to: CGPoint(x: r.minX - topRadius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + topRadius, y: r.minY))

        // Top-right outward flare: smooth quad curve from the extended
        // top-right point inward and down to the right vertical wall.
        // Control point sits at the corner where the extended top edge
        // would meet a square corner — pulls the curve into a clean
        // concave-from-outside / convex-from-inside arc.
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY + topRadius),
            control: CGPoint(x: r.maxX, y: r.minY)
        )

        // Right vertical wall down to the bottom-right curve.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))

        // Bottom-right convex (existing).
        p.addArc(
            center: CGPoint(x: r.maxX - bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))

        // Bottom-left convex (existing).
        p.addArc(
            center: CGPoint(x: r.minX + bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left vertical wall up to where the top-left flare begins.
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + topRadius))

        // Top-left outward flare: mirror of top-right.
        p.addQuadCurve(
            to: CGPoint(x: r.minX - topRadius, y: r.minY),
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
