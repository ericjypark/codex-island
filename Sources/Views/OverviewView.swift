import SwiftUI

struct OverviewView: View {
    @ObservedObject private var costStore = CostStore.shared

    var body: some View {
        OverviewContent(
            allDays: OverviewContent.joinDays(buckets: Dictionary(uniqueKeysWithValues:
                IslandProvider.allCases.map { ($0, costStore.cost(for: $0).dailyTokens) }
            )),
            loading: costStore.loading
        )
    }
}

/// Minimal contribution-style view. Powered by the same local log scan as
/// the cost page, but framed as usage history: cell intensity is token
/// volume, and cell hue follows the dominant provider for that day.
private struct OverviewContent: View {
    let allDays: [OverviewDay]
    let loading: Bool
    @State private var selectedDate: Date?
    @State private var selectedProvider: IslandProvider?

    private var days: [OverviewDay] {
        guard let selectedProvider else { return allDays }
        return allDays.map { day in
            OverviewDay(date: day.date,
                        tokens: [selectedProvider: day.tokens[selectedProvider] ?? 0],
                        isFuture: day.isFuture)
        }
    }

    private var totalTokens: Int { days.reduce(0) { $0 + $1.totalTokens } }
    private var activeDays: Int { days.filter { $0.totalTokens > 0 }.count }

    private var displayedUsage: [ProviderTokenUsage] {
        let history = allDays
        let selected = selectedDate.flatMap { date in
            history.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        }
        return IslandProvider.allCases.compactMap { provider in
            let tokens = history.reduce(0) { $0 + ($1.tokens[provider] ?? 0) }
            guard tokens > 0 else { return nil }
            return ProviderTokenUsage(provider: provider,
                                      tokens: selected.map { $0.tokens[provider] ?? 0 } ?? tokens)
        }
    }

    private var selectedDay: OverviewDay? {
        guard let selectedDate else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return days.first { cal.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var displayedTokens: Int {
        selectedDay?.totalTokens ?? totalTokens
    }

    var body: some View {
        overviewContent
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary

            ContributionGrid(days: days, selectedDate: $selectedDate)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedDay {
                DayDetailStrip(day: selectedDay)
                .transition(.detailReveal)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(.detailExpand, value: selectedDate)
        .onReceive(ScreenPref.shared.$screen.dropFirst()) { screen in
            guard screen != .overview else { return }
            if selectedDate != nil {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedDate = nil
                }
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryLabel)
                    .font(Typography.sectionLabel)
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.formatTokens(displayedTokens).value)
                        .font(Typography.chartValue)
                        .foregroundStyle(.white)
                    Text(Self.formatTokens(displayedTokens).unit)
                        .font(Typography.unit)
                        .foregroundStyle(.white.opacity(0.40))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Text(summarySubline)
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.50))
                if loading {
                    Text(L10n.tr("Syncing"))
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.36))
                }
            }
            .padding(.bottom, 5)

            Spacer(minLength: 0)

            ProviderSplitRow(usage: displayedUsage, selectedProvider: $selectedProvider)
                .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var summaryLabel: String {
        guard let selectedDay else {
            let yearLabel = L10n.tr("%@ TOKENS", Self.currentYearString)
            return selectedProvider.map { "\($0.name.uppercased()) · \(yearLabel)" } ?? yearLabel
        }
        return Self.dayLabelFormatter.string(from: selectedDay.date).uppercased()
    }

    private var summarySubline: String {
        guard let selectedDay else { return L10n.tr("%d Active Days", activeDays) }
        return selectedDay.dominanceLabel
    }

    private var summaryAccessibilityLabel: String {
        let period = selectedDay.map { Self.dayLabelFormatter.string(from: $0.date) } ?? Self.currentYearString
        return "\(period): \(Self.formatTokensSpoken(displayedTokens)). " + displayedUsage.filter { selectedProvider == nil || $0.provider == selectedProvider }.map {
            "\($0.provider.name) \(Self.formatTokensSpoken($0.tokens))"
        }.joined(separator: ", ")
    }

    static func joinDays(buckets: [IslandProvider: [DailyTokenBucket]]) -> [OverviewDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        let nextYear = cal.date(byAdding: .year, value: 1, to: start) ?? today
        let dayCount = cal.dateComponents([.day], from: start, to: nextYear).day ?? 365
        var totals: [Date: [IslandProvider: Int]] = [:]
        for (provider, history) in buckets {
            for bucket in history {
                let day = cal.startOfDay(for: bucket.dayStart)
                totals[day, default: [:]][provider, default: 0] += bucket.tokens
            }
        }
        return (0..<dayCount).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
            return OverviewDay(date: day, tokens: totals[day] ?? [:], isFuture: day > today)
        }
    }

    fileprivate static func formatTokens(_ n: Int) -> (value: String, unit: String) {
        let v = Double(n)
        if n < 1_000 { return ("\(n)", "tok") }
        if n < 10_000 { return (String(format: "%.1f", v / 1_000), "k") }
        if n < 1_000_000 { return (String(format: "%.0f", v / 1_000), "k") }
        if n < 1_000_000_000 { return (String(format: "%.1f", v / 1_000_000), "M") }
        return (String(format: "%.1f", v / 1_000_000_000), "B")
    }

    fileprivate static func formatTokensSpoken(_ n: Int) -> String {
        let formatted = formatTokens(n)
        return L10n.tr("%@ %@ tokens", formatted.value, formatted.unit)
    }

    fileprivate static func formatExactTokens(_ n: Int) -> String {
        integerFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = L10n.locale
        return formatter
    }()

    fileprivate static var currentYearString: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)"
    }
}

private struct ProviderTokenUsage: Identifiable {
    let provider: IslandProvider
    let tokens: Int
    var id: IslandProvider { provider }
}

private struct OverviewDay: Identifiable {
    let date: Date
    let tokens: [IslandProvider: Int]
    var isFuture = false

    var id: Date { date }
    var totalTokens: Int { tokens.values.reduce(0, +) }
    var usage: [ProviderTokenUsage] {
        IslandProvider.allCases.compactMap { provider in
            let count = tokens[provider] ?? 0
            return count > 0 ? ProviderTokenUsage(provider: provider, tokens: count) : nil
        }
    }
    var leadingProvider: IslandProvider? {
        usage.max { $0.tokens < $1.tokens }?.provider
    }
    var dominantProvider: IslandProvider? {
        guard totalTokens > 0 else { return nil }
        return usage.first { Double($0.tokens) / Double(totalTokens) >= 0.60 }?.provider
    }
    var dominanceLabel: String {
        guard totalTokens > 0 else { return L10n.tr("No Activity") }
        return dominantProvider.map { "Mostly " + $0.name } ?? L10n.tr("Mixed Use")
    }
}

private struct ContributionGrid: View {
    let days: [OverviewDay]
    @Binding var selectedDate: Date?

    private var intensityScale: TokenIntensityScale {
        TokenIntensityScale(values: days.map(\.totalTokens))
    }

    var body: some View {
        let scale = intensityScale

        VStack(alignment: .leading, spacing: 7) {
            MonthRail(marks: monthMarks)
                .frame(width: gridWidth, height: 12, alignment: .leading)

            HStack(alignment: .top, spacing: gridSpacing) {
                ForEach(weeks) { week in
                    VStack(spacing: verticalSpacing) {
                        ForEach(Array(week.slots.enumerated()), id: \.offset) { _, slot in
                            switch slot {
                            case .spacer:
                                Color.clear.frame(width: cellSize, height: cellSize)
                            case .day(let day):
                                if day.isFuture {
                                    FutureContributionCell(day: day.date, cellSize: cellSize)
                                } else {
                                    ContributionCell(
                                        day: day,
                                        intensityScale: scale,
                                        cellSize: cellSize,
                                        isSelected: isSelected(day)
                                    ) {
                                        toggleSelection(day)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: cellSize, height: gridHeight, alignment: .top)
                }
            }
            .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        }
        .frame(width: gridWidth, height: gridHeight + 19, alignment: .topLeading)
        .frame(maxWidth: .infinity, minHeight: gridHeight + 19, maxHeight: gridHeight + 19, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Daily token usage in %@", OverviewContent.currentYearString))
    }

    private var weeks: [ContributionWeek] {
        guard let first = days.first?.date,
              let today = days.last?.date else { return [] }
        let cal = calendar
        let start = weekStart(containing: first, calendar: cal)
        let map = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        var out: [ContributionWeek] = []
        out.reserveCapacity(weekCount)

        for week in 0..<weekCount {
            guard let weekStartDate = cal.date(byAdding: .day, value: week * 7, to: start) else {
                continue
            }
            var slots: [ContributionSlot] = []
            slots.reserveCapacity(7)

            for row in 0..<7 {
                let offset = week * 7 + row
                guard let date = cal.date(byAdding: .day, value: offset, to: start) else {
                    slots.append(.spacer)
                    continue
                }
                if date < first || date > today {
                    slots.append(.spacer)
                } else if let day = map[date] {
                    slots.append(.day(day))
                }
            }
            out.append(ContributionWeek(id: weekStartDate, slots: slots))
        }
        return out
    }

    private var weekCount: Int {
        guard let first = days.first?.date,
              let last = days.last?.date else { return 1 }
        let cal = calendar
        let start = weekStart(containing: first, calendar: cal)
        let daySpan = cal.dateComponents([.day], from: start, to: last).day ?? 0
        return max(1, daySpan / 7 + 1)
    }

    private var cellSize: CGFloat {
        return 11.6
    }

    private var gridSpacing: CGFloat {
        return 2.35
    }

    private var verticalSpacing: CGFloat {
        return gridSpacing
    }

    private var gridWidth: CGFloat {
        CGFloat(weekCount) * cellSize + CGFloat(max(0, weekCount - 1)) * gridSpacing
    }

    private var gridHeight: CGFloat {
        CGFloat(7) * cellSize + CGFloat(6) * gridSpacing
    }

    private var monthMarks: [MonthMark] {
        guard let first = days.first?.date,
              let last = days.last?.date else { return [] }
        let cal = calendar
        let start = weekStart(containing: first, calendar: cal)
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: first)) ?? first
        var marks: [MonthMark] = []

        while cursor <= last {
            let dayOffset = cal.dateComponents([.day], from: start, to: cursor).day ?? 0
            let weekIndex = max(0, dayOffset / 7)
            marks.append(MonthMark(
                id: cursor,
                label: Self.monthFormatter.string(from: cursor),
                x: CGFloat(weekIndex) * (cellSize + gridSpacing)
            ))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return marks
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    private func isSelected(_ day: OverviewDay) -> Bool {
        guard !day.isFuture else { return false }
        guard let selectedDate else { return false }
        return calendar.isDate(day.date, inSameDayAs: selectedDate)
    }

    private func toggleSelection(_ day: OverviewDay) {
        guard !day.isFuture else { return }
        if isSelected(day) {
            selectedDate = nil
        } else {
            selectedDate = day.date
        }
    }

    private func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: date) ?? date
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()
}

private struct ContributionWeek: Identifiable {
    let id: Date
    let slots: [ContributionSlot]
}

private enum ContributionSlot {
    case spacer
    case day(OverviewDay)
}

private struct MonthMark: Identifiable {
    let id: Date
    let label: String
    let x: CGFloat
}

private struct MonthRail: View {
    let marks: [MonthMark]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                Text(mark.label)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.30))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: mark.x, y: 0)
            }
        }
    }
}

private struct FutureContributionCell: View {
    let day: Date
    let cellSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.white.opacity(0.012))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.030), lineWidth: 0.5)
            }
        .frame(width: cellSize, height: cellSize)
        .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        min(3, cellSize * 0.22)
    }
}

private struct ContributionCell: View {
    let day: OverviewDay
    let intensityScale: TokenIntensityScale
    let cellSize: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            cellFill
        }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(strokeColor, lineWidth: isSelected ? 1.2 : 0.5)
            }
            .frame(width: cellSize, height: cellSize)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onHover { hovering = $0 }
            .help(helpText)
            .accessibilityElement()
            .accessibilityLabel(helpText)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var cellFill: some View {
        let opacity = day.totalTokens > 0 ? intensityScale.opacity(for: day.totalTokens) : 0.035
        if let provider = day.leadingProvider {
            provider.color.opacity(opacity)
                .overlay(alignment: .bottom) {
                    if day.usage.count > 1 {
                        HStack(spacing: 0) {
                            ForEach(day.usage) { item in
                                item.provider.color.opacity(max(0.35, opacity))
                                    .frame(width: cellSize * CGFloat(Double(item.tokens) / Double(day.totalTokens)))
                            }
                        }
                        .frame(height: max(2, cellSize * 0.20))
                    }
                }
        } else {
            Color.white.opacity(opacity)
        }
    }

    private var cornerRadius: CGFloat { min(3, cellSize * 0.22) }

    private var strokeColor: Color {
        if isSelected { return .white.opacity(0.72) }
        if hovering { return .white.opacity(0.22) }
        guard day.totalTokens > 0 else { return .white.opacity(0.04) }
        return .white.opacity(0.06 + Double(intensityScale.level(for: day.totalTokens)) * 0.012)
    }

    private var helpText: String {
        L10n.tr(
            "%@: %@, %@",
            Self.dayFormatter.string(from: day.date),
            OverviewContent.formatTokensSpoken(day.totalTokens),
            dominanceLabel
        ) + (day.usage.isEmpty ? "" : "\n" + day.usage.map { item in
            let percent = Double(item.tokens) / Double(day.totalTokens) * 100
            return "\(item.provider.name): \(String(format: "%.1f", percent))%"
        }.joined(separator: ", "))
    }

    private var dominanceLabel: String {
        day.dominanceLabel
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

private struct TokenIntensityScale {
    private let values: [Int]

    init(values: [Int]) {
        self.values = values.filter { $0 > 0 }.sorted()
    }

    func level(for tokens: Int) -> Int {
        guard tokens > 0, !values.isEmpty else { return 0 }
        let rank = Double(upperBound(tokens)) / Double(values.count)
        switch rank {
        case ..<0.15: return 1
        case ..<0.35: return 2
        case ..<0.60: return 3
        case ..<0.80: return 4
        case ..<0.93: return 5
        default:      return 6
        }
    }

    func opacity(for tokens: Int) -> Double {
        switch level(for: tokens) {
        case 1:  return 0.14
        case 2:  return 0.26
        case 3:  return 0.42
        case 4:  return 0.62
        case 5:  return 0.82
        case 6:  return 0.98
        default: return 0.035
        }
    }

    private func upperBound(_ value: Int) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

private struct DayDetailStrip: View {
    let day: OverviewDay

    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(.white.opacity(0.075))
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.detailFormatter.string(from: day.date).uppercased())
                        .font(Typography.sectionLabel)
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    Text(L10n.tr("All Tokens"))
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)
                }
                .frame(width: 116, alignment: .leading)

                Spacer(minLength: 0)

                detailMetric(
                    label: L10n.tr("TOTAL"),
                    spokenLabel: L10n.tr("Total"),
                    value: day.totalTokens,
                    color: .white.opacity(0.78),
                    dimmed: true
                )

                ForEach(day.usage) { item in
                    detailMetric(label: item.provider.name.uppercased(), spokenLabel: item.provider.name,
                                 value: item.tokens, color: item.provider.color)
                }
            }
        }
        .frame(height: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func detailMetric(
        label: String,
        spokenLabel: String? = nil,
        value: Int,
        color: Color,
        dimmed: Bool = false
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(Typography.chip)
                .tracking(0.5)
                .foregroundStyle(color.opacity(dimmed ? 0.70 : 0.82))
                .lineLimit(1)

            Text(OverviewContent.formatExactTokens(value))
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .frame(width: 82, alignment: .trailing)
        .help(L10n.tr("%@: %@ tokens", spokenLabel ?? label, OverviewContent.formatExactTokens(value)))
    }

    private var accessibilityLabel: String {
        "\(Self.detailFormatter.string(from: day.date)), all tokens. Total \(OverviewContent.formatTokensSpoken(day.totalTokens)), " + day.usage.map {
            "\($0.provider.name) \(OverviewContent.formatTokensSpoken($0.tokens))"
        }.joined(separator: ", ")
    }

    private static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}

private struct ProviderSplitRow: View {
    let usage: [ProviderTokenUsage]
    @Binding var selectedProvider: IslandProvider?
    private var total: Int { usage.reduce(0) { $0 + $1.tokens } }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 3) {
            ForEach(usage) { item in
                Button {
                    selectedProvider = selectedProvider == item.provider ? nil : item.provider
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(item.provider.color).frame(width: 5, height: 5)
                        Text("\(item.provider.name) \(share(item.tokens))")
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(selectedProvider == item.provider ? 0.95 : 0.46))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .background(selectedProvider == item.provider ? item.provider.color.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selectedProvider == item.provider ? "Show all providers" : "Show only \(item.provider.name)")
                .accessibilityLabel("\(item.provider.name), \(share(item.tokens)) of all tokens")
                .accessibilityAddTraits(selectedProvider == item.provider ? .isSelected : [])
            }
        }
        .frame(width: 230)
    }

    private func share(_ value: Int) -> String {
        guard total > 0 else { return "0%" }
        let percent = Double(value) / Double(total) * 100
        if value > 0 && percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }
}
