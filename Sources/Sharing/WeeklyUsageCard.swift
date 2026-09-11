import SwiftUI
import AppKit

struct WeeklyUsageCard: View {
    let snapshot: WeeklyUsageSnapshot
    let format: WeeklyCardFormat
    var signature = ""
    var metric: WeeklyCardMetric = .apiValue

    private var tier: WeeklyCardTier { snapshot.tier(for: metric) }
    private var theme: WeeklyCardTheme { tier.theme }
    private var compact: Bool { format == .square }
    private var tokens: (value: String, unit: String) {
        WeeklyUsageSnapshot.compactTokens(snapshot.totalTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.isDemo ? "Demo · \(snapshot.dateLabel)" : snapshot.dateLabel)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                Text(signature.trimmingCharacters(in: .whitespacesAndNewlines))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.secondary)

            heading
                .padding(.top, compact ? 12 : 26)

            WeeklyValueFlow(snapshot: snapshot, theme: theme, metric: metric)
                .frame(maxHeight: .infinity)
                .padding(.top, compact ? 14 : 28)
                .padding(.bottom, compact ? 14 : 24)

            providerLegend
            if metric == .apiValue {
                Text("API-rate estimate, not a bill.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .padding(.top, compact ? 8 : 12)
            }

            footer
                .padding(.top, compact ? 14 : 24)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, format == .story ? 88 : 32)
        .frame(width: format.size.width, height: format.size.height)
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .environment(\.colorScheme, theme == .paper ? .light : .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.shareText(metric: metric))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Text(metric == .apiValue ? snapshot.valueHeadline : snapshot.period.tokenHeadline)
                    .font(.system(size: compact ? 32 : 36, weight: .medium))
                    .tracking(-1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if metric == .apiValue, let milestone = snapshot.valueMilestone {
                    WeeklyMilestoneSeal(milestone: milestone, theme: theme, compact: compact)
                }
            }

            if metric == .apiValue {
                moneyHeadline
                    .frame(height: compact ? 82 : 126, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, compact ? 2 : 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.hasPartialPricing ? "Known API value · USD" : "API value · USD")
                        .foregroundStyle(theme.secondary)
                    Spacer(minLength: 8)
                    Text(snapshot.period.valueQualifier)
                }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 2)
                    .padding(.bottom, compact ? 8 : 18)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tokens.value).tracking(-3)
                    Text(tokens.unit).tracking(-2).foregroundStyle(theme.secondary)
                }
                .font(.system(size: compact ? 94 : 112, weight: .regular, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.vertical, compact ? 0 : 2)
            }

            HStack(spacing: 0) {
                Text(metric == .apiValue ? snapshot.tokenLabel : snapshot.totalTokens == 1 ? "token" : "tokens")
                    .foregroundStyle(theme.foreground)
                Text("  ·  \(snapshot.activityLabel)")
                    .foregroundStyle(theme.secondary)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private var moneyHeadline: some View {
        let formatted = WeeklyUsageSnapshot.money(snapshot.totalDollars)
        let subcent = formatted.hasPrefix("<")
        let amount = formatted.dropFirst(subcent ? 2 : 1).split(separator: ".")
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(subcent ? "<$" : "$")
                .font(.system(size: compact ? 42 : 50, weight: .regular, design: .rounded))
                .foregroundStyle(theme.secondary)
                .padding(.trailing, 3)
            Text(amount.first.map(String.init) ?? "0")
                .font(.system(size: compact ? 90 : 108, weight: .regular, design: .rounded))
                .tracking(-3)
            Text(".\(amount.count > 1 ? String(amount[1]) : "00")\(snapshot.valueSuffix)")
                .font(.system(size: compact ? 34 : 40, weight: .regular, design: .rounded))
                .foregroundStyle(theme.secondary)
                .padding(.leading, 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.42)
    }

    private var providerLegend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 10) {
            ForEach(snapshot.rankedProviders(for: metric)) { item in
                HStack(spacing: 7) {
                    Circle().fill(theme.color(for: item.provider))
                        .frame(width: 7, height: 7)
                    Text(item.provider.name)
                        .foregroundStyle(theme.foreground)
                    Spacer(minLength: 8)
                    Text(providerValue(item))
                        .foregroundStyle(theme.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }

    private func providerValue(_ item: WeeklyUsageSnapshot.ProviderTotal) -> String {
        guard metric == .apiValue else { return snapshot.percentLabel(for: item.tokens) }
        if item.unpricedTokens == item.tokens { return "Unpriced" }
        return WeeklyUsageSnapshot.money(item.dollars) + (item.unpricedTokens > 0 ? "+" : "")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(theme.rule).frame(height: 0.5)
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    WeeklyCardBrandMark()
                        .frame(width: 17, height: 17)
                    Text("CodexIsland")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.3)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(metric == .apiValue ? snapshot.valueChallenge : snapshot.period.tokenCallToAction)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                    Text("codexisland.com")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
    }

}

private struct WeeklyMilestoneSeal: View {
    let milestone: WeeklyValueMilestone
    let theme: WeeklyCardTheme
    let compact: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(milestone.label)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("CLUB")
                .font(.system(size: 8, weight: .semibold))
                .tracking(2.5)
        }
        .padding(9)
        .frame(width: compact ? 68 : 76, height: compact ? 56 : 66)
        .background {
            WeeklySealOutline().stroke(theme.foreground.opacity(0.65), lineWidth: 0.75)
            WeeklySealOutline().stroke(theme.rule, lineWidth: 0.5).padding(4)
        }
        .accessibilityLabel("\(milestone.label) API value milestone")
    }
}

private struct WeeklySealOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = 10
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            let corners = [
                CGPoint(x: rect.maxX - cut, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + cut),
                CGPoint(x: rect.maxX, y: rect.maxY - cut),
                CGPoint(x: rect.maxX - cut, y: rect.maxY),
                CGPoint(x: rect.minX + cut, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - cut),
                CGPoint(x: rect.minX, y: rect.minY + cut)
            ]
            for point in corners { path.addLine(to: point) }
            path.closeSubpath()
        }
    }
}

private struct WeeklyCardBrandMark: View {
    private static let image = Bundle.main.url(forResource: "codexisland_logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
        } else {
            Image(systemName: "curlybraces").resizable().scaledToFit()
        }
    }
}

private struct WeeklyValueFlow: View {
    let snapshot: WeeklyUsageSnapshot
    let theme: WeeklyCardTheme
    let metric: WeeklyCardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric == .apiValue ? "Cumulative API value" : "Cumulative tokens")
                Spacer()
                Text(snapshot.durationLabel)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondary)
            Canvas { context, size in draw(in: &context, size: size) }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let baseline = max(16, size.height - 24)
        let height = max(1, baseline - 12)
        let inset: CGFloat = 12
        let width = max(1, size.width - inset * 2)
        let total = metric == .apiValue ? snapshot.totalDollars : Double(snapshot.totalTokens)
        let maximum = max(total, 0.000001)
        let dayCount = max(1, snapshot.days.count)
        let indices = snapshot.chartPointIndices
        func points(_ values: [Double]) -> [CGPoint] {
            indices.map { index in
                CGPoint(x: inset + width * CGFloat(index) / CGFloat(dayCount),
                        y: baseline - height * CGFloat(values[index] / maximum))
            }
        }
        var boundary = Array(repeating: 0.0, count: dayCount + 1)
        for item in snapshot.rankedProviders(for: metric) {
            let values = snapshot.cumulativeValues(for: item.provider, metric: metric)
            let upper = zip(boundary, values).map(+)
            let lowerPoints = points(boundary)
            let upperPoints = points(upper)
            var band = curve(upperPoints)
            if let last = lowerPoints.last { band.addLine(to: last) }
            appendCurve(Array(lowerPoints.reversed()), to: &band)
            band.closeSubpath()
            let color = theme.color(for: item.provider)
            context.fill(band, with: .linearGradient(
                Gradient(colors: [color, color.opacity(0.70), color.opacity(0.12)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: baseline)))
            context.stroke(curve(upperPoints), with: .color(color), lineWidth: 1.2)
            boundary = upper
        }

        let ridge = points(boundary)
        if total > 0 {
            context.stroke(curve(ridge), with: .color(theme.foreground.opacity(0.85)), lineWidth: 1.5)
            let markerIndices = Set(snapshot.chartLabelDayIndices.map { $0 + 1 })
            for (index, point) in zip(indices, ridge) where markerIndices.contains(index) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                             with: .color(theme.foreground))
            }
            if let end = ridge.last {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                             with: .color(theme.foreground))
            }
        }
        var axis = Path()
        axis.move(to: CGPoint(x: inset, y: baseline))
        axis.addLine(to: CGPoint(x: size.width - inset, y: baseline))
        context.stroke(axis, with: .color(theme.rule), lineWidth: 0.5)
        for index in snapshot.chartLabelDayIndices {
            let label = Text(snapshot.chartLabel(for: snapshot.days[index]))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondary)
            context.draw(label, at: CGPoint(x: inset + width * CGFloat(index + 1) / CGFloat(dayCount), y: baseline + 16),
                         anchor: index == dayCount - 1 ? .trailing : .center)
        }
    }

    private func curve(_ points: [CGPoint]) -> Path {
        var path = Path()
        if let start = points.first { path.move(to: start) }
        appendCurve(points, to: &path)
        return path
    }

    private func appendCurve(_ points: [CGPoint], to path: inout Path) {
        for (start, end) in zip(points, points.dropFirst()) {
            // Shared interpolation keeps cumulative bands ordered, with no overshoot.
            let middle = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y),
                          control2: CGPoint(x: middle, y: end.y))
        }
    }
}
