import SwiftUI

enum SparklinePath {
    static func line(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        let knots = simplified(points, tolerance: 0.6)
        for index in 1..<(knots.count - 1) {
            let previous = knots[index - 1], corner = knots[index], next = knots[index + 1]
            let incoming = hypot(corner.x - previous.x, corner.y - previous.y)
            let outgoing = hypot(next.x - corner.x, next.y - corner.y)
            guard incoming > 0, outgoing > 0 else { continue }
            let radius = min(7, incoming / 2, outgoing / 2)
            let entry = CGPoint(x: corner.x + (previous.x - corner.x) * radius / incoming,
                                y: corner.y + (previous.y - corner.y) * radius / incoming)
            let exit = CGPoint(x: corner.x + (next.x - corner.x) * radius / outgoing,
                               y: corner.y + (next.y - corner.y) * radius / outgoing)
            path.addLine(to: entry)
            path.addQuadCurve(to: exit, control: corner)
        }
        if let last = knots.last { path.addLine(to: last) }
        return path
    }

    // Remove subpixel stair steps before rounding; recorded values remain untouched.
    private static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var retained: Set<Int> = [0, points.count - 1]
        var intervals = [(0, points.count - 1)]
        while let (first, last) = intervals.popLast() {
            guard last > first + 1 else { continue }
            let start = points[first], end = points[last]
            let dx = end.x - start.x, dy = end.y - start.y
            let squaredLength = dx * dx + dy * dy
            var furthest = first, maximum: CGFloat = tolerance * tolerance
            for index in (first + 1)..<last {
                let point = points[index]
                let fraction = squaredLength > 0
                    ? min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength)) : 0
                let distanceX = point.x - start.x - fraction * dx
                let distanceY = point.y - start.y - fraction * dy
                let squaredDistance = distanceX * distanceX + distanceY * distanceY
                if squaredDistance > maximum {
                    maximum = squaredDistance
                    furthest = index
                }
            }
            if furthest != first {
                retained.insert(furthest)
                intervals.append((first, furthest))
                intervals.append((furthest, last))
            }
        }
        return retained.sorted().map { points[$0] }
    }

    static func area(under line: Path, points: [CGPoint], baseline: CGFloat) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var area = line
        area.addLine(to: CGPoint(x: last.x, y: baseline))
        area.addLine(to: CGPoint(x: first.x, y: baseline))
        area.closeSubpath()
        return area
    }
}
