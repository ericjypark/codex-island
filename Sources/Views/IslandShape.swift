import SwiftUI

/// The notch silhouette. The bottom corners curve outward generously to
/// mirror the physical notch's inner curves; the top corners get a smaller
/// rounding so the silhouette flows smoothly into the menu bar / screen
/// edge instead of cutting off at a hard 90°.
struct IslandShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let topRadius: CGFloat = 8
        let bottomRadius: CGFloat = 14
        var p = Path()

        // Top edge — start just past the top-left corner curve.
        p.move(to: CGPoint(x: r.minX + topRadius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius, y: r.minY))

        // Top-right rounded corner.
        p.addArc(
            center: CGPoint(x: r.maxX - topRadius, y: r.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right side down to the bottom-right curve.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))

        // Bottom-right rounded corner.
        p.addArc(
            center: CGPoint(x: r.maxX - bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))

        // Bottom-left rounded corner.
        p.addArc(
            center: CGPoint(x: r.minX + bottomRadius, y: r.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left side up to the top-left curve.
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + topRadius))

        // Top-left rounded corner.
        p.addArc(
            center: CGPoint(x: r.minX + topRadius, y: r.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
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
