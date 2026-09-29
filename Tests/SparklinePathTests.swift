import SwiftUI

@main
struct SparklinePathTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func equal(_ a: CGPoint, _ b: CGPoint) -> Bool {
            abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001
        }
        check(SparklinePath.line(through: []).isEmpty, "Empty history must stay empty")
        let single = CGPoint(x: 3, y: 35)
        check(SparklinePath.line(through: [single]).cgPath.currentPoint == single, "Single reading is preserved")

        let histories: [[CGFloat]] = [
            [0, 0, 0, 0], [100, 100, 100], [5, 20],
            [5, 6, 12, 35, 35, 40, 48],
            [30, 30, 80, 0, 0, 12, 14],
            [0, 100, 0, 100, 0],
            (0..<1000).map { CGFloat($0 % 101) }
        ]
        for history in histories {
            for remaining in [false, true] {
                for width: CGFloat in [76, 164, 240] {
                    let points: [CGPoint] = history.enumerated().map { index, value in
                        let fraction = CGFloat(index) / CGFloat(history.count - 1)
                        let displayValue: CGFloat = remaining ? 100 - value : value
                        let x: CGFloat = 3 + fraction * (width - 6)
                        let y: CGFloat = 3 + (1 - displayValue / 100) * 32
                        return CGPoint(x: x, y: y)
                    }
                    let path = SparklinePath.line(through: points)
                    var drawn: [CGPoint] = []
                    var cursor = points[0]
                    let minimum = points.map(\.y).min() ?? 0
                    let maximum = points.map(\.y).max() ?? 0
                    var curves = 0
                    path.cgPath.applyWithBlock { element in
                        let data = element.pointee
                        switch data.type {
                        case .moveToPoint:
                            cursor = data.points[0]
                            check(equal(cursor, points[0]), "First measurement moved")
                            drawn.append(cursor)
                        case .addLineToPoint:
                            let end = data.points[0]
                            for step in 1...40 {
                                let t = CGFloat(step) / 40
                                drawn.append(CGPoint(x: cursor.x + (end.x - cursor.x) * t,
                                                     y: cursor.y + (end.y - cursor.y) * t))
                            }
                            cursor = end
                        case .addQuadCurveToPoint:
                            let control = data.points[0], end = data.points[1]
                            for step in 1...40 {
                                let t = CGFloat(step) / 40, u = 1 - t
                                let startWeight: CGFloat = u * u
                                let controlWeight: CGFloat = 2 * u * t
                                let endWeight: CGFloat = t * t
                                let x: CGFloat = startWeight * cursor.x + controlWeight * control.x + endWeight * end.x
                                let y: CGFloat = startWeight * cursor.y + controlWeight * control.y + endWeight * end.y
                                drawn.append(CGPoint(x: x, y: y))
                            }
                            cursor = end
                            curves += 1
                        default:
                            check(false, "Unexpected path element")
                        }
                    }
                    for (previous, point) in zip(drawn, drawn.dropFirst()) {
                        check(point.x >= previous.x - 0.0001, "Curve doubled back in time")
                        check(point.y >= minimum - 0.0001 && point.y <= maximum + 0.0001,
                              "Curve invented an out-of-range value")
                    }
                    if let last = points.last {
                        check(equal(path.cgPath.currentPoint, last), "Latest reading moved")
                    }
                    if history == [0, 100, 0, 100, 0] {
                        check(curves > 0, "Sharp reversals must have rounded corners")
                    }
                    let area = SparklinePath.area(under: path, points: points, baseline: 38)
                    check(abs(area.boundingRect.maxY - 38) < 0.0001, "Fill does not meet the baseline")
                }
            }
        }
        print("PASS \(checks) sparkline geometry checks")
    }
}
