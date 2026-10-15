import SwiftUI

struct UnrollingQuotaShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, progress))
        let stroke = 2 + amount
        let centerY = rect.height / 2
        let barY = min(rect.height - 3, centerY + 8.5)
        if amount >= 0.99999 {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 1.5, y: rect.minY + barY))
            path.addLine(to: CGPoint(x: rect.maxX - 1.5, y: rect.minY + barY))
            return path
        }

        // Keep the curl small while a tangent grows into the bar. Stretching
        // the entire arc makes the quota appear to spin during the hover.
        let turn = 2 * CGFloat.pi * (1 - amount)
        let radius = 9 * (1 - amount)
        let startX = rect.minX + stroke / 2 + radius
        let tangentX = startX + (rect.width - 3) * amount
        let topY = rect.minY + (centerY - 9) * (1 - amount) + barY * amount
        var path = Path()
        path.move(to: CGPoint(x: startX, y: topY))
        path.addLine(to: CGPoint(x: tangentX, y: topY))
        for index in 1...64 {
            let angle = turn * CGFloat(index) / 64
            path.addLine(to: CGPoint(
                x: tangentX + radius * sin(angle),
                y: topY + radius * (1 - cos(angle))
            ))
        }
        return path
    }
}
