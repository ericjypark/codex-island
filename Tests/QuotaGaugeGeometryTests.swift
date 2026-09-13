import SwiftUI

@main
struct QuotaGaugeGeometryTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        for height: CGFloat in [24, 38] {
            for origin in [CGPoint.zero, CGPoint(x: 12, y: 30)] {
                let rect = CGRect(origin: origin, size: CGSize(width: 76, height: height))
                for step in 0...100 {
                    let amount = CGFloat(step) / 100
                    let shape = UnrollingQuotaShape(progress: amount)
                    let path = shape.path(in: rect)
                    let ink = path.boundingRect.insetBy(dx: -(2 + amount) / 2, dy: -(2 + amount) / 2)
                    check(rect.insetBy(dx: -0.001, dy: -0.001).contains(ink), "Gauge escapes its bounds at \(amount), height \(height)")
                    let points = vertices(path)
                    check(points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "Gauge contains a non-finite point")
                    check(!selfIntersects(points), "Unrolling arc crosses itself at \(amount)")
                }
                let circle = UnrollingQuotaShape(progress: 0).path(in: rect)
                check(abs(circle.boundingRect.width - 18) < 0.001 && abs(circle.boundingRect.height - 18) < 0.001, "Compact circle must retain its 20 pt footprint")
                let start = vertices(circle)[0]
                let end = circle.cgPath.currentPoint
                check(hypot(start.x - end.x, start.y - end.y) < 0.001, "Compact ring has an open seam")
                let bar = UnrollingQuotaShape(progress: 1).path(in: rect)
                check(abs(bar.boundingRect.width - 73) < 0.001 && bar.boundingRect.height == 0, "Peek must settle into a straight 76 pt bar including caps")
                let almost = UnrollingQuotaShape(progress: 0.9999).path(in: rect).boundingRect
                check(abs(almost.maxY - bar.boundingRect.maxY) < 0.01, "Final unroll frame jumps")
            }
        }
        print("PASS \(checks) quota gauge geometry checks")
    }

    private static func vertices(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.cgPath.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            default: break
            }
        }
        return points
    }

    private static func selfIntersects(_ points: [CGPoint]) -> Bool {
        guard points.count >= 4 else { return false }
        func side(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for first in 0..<(points.count - 3) {
            for second in (first + 2)..<(points.count - 1) {
                let a = points[first], b = points[first + 1]
                let c = points[second], d = points[second + 1]
                if side(a, b, c) * side(a, b, d) < -0.000001,
                   side(c, d, a) * side(c, d, b) < -0.000001 { return true }
            }
        }
        return false
    }
}
