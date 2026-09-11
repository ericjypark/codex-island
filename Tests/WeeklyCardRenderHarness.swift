import AppKit
import SwiftUI

@main
struct WeeklyCardRenderHarness {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--studio") {
            WeeklyCardWindowController.shared.show()
            app.run()
            return
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "notes/weekly-card/renders")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let now = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z") else { return }
        let interval = WeeklyCardPeriod.lastSevenDays.interval(now: now, calendar: calendar)
        let values: [IslandProvider: [Int]] = [
            .claude: [3_200_000, 1_800_000, 5_100_000, 8_400_000, 2_200_000, 4_800_000, 6_200_000],
            .codex: [9_300_000, 7_600_000, 2_400_000, 6_200_000, 10_800_000, 15_400_000, 12_300_000],
            .antigravity: [1_200_000, 0, 1_900_000, 2_800_000, 1_000_000, 3_600_000, 2_100_000],
            .grok: [0, 0, 0, 0, 400_000, 100_000, 500_000]
        ]
        let costs: [IslandProvider: [Double]] = [
            .claude: [71.2, 38.4, 91.25, 182.35, 48.70, 121.80, 148.16],
            .codex: [45.10, 29.40, 17.60, 67.10, 56.70, 109.70, 97.80],
            .antigravity: [11.70, 0, 14.50, 39.70, 12.55, 44.80, 25.40],
            .grok: [0, 0, 0, 0, 8.55, 2.30, 10.15]
        ]
        let buckets = Dictionary(uniqueKeysWithValues: values.map { provider, values in
            (provider,
            values.enumerated().map { index, value in
                DailyTokenBucket(dayStart: calendar.date(byAdding: .day, value: index, to: interval.start) ?? now,
                                 tokens: value, billableTokens: value / 10,
                                 dollars: costs[provider]?[index], unpricedTokens: 0)
            })
        })
        let snapshot = WeeklyUsageSnapshot.make(buckets: buckets, now: now, calendar: calendar, isDemo: true)
        for (expectedTier, multiplier) in [(WeeklyCardTier.white, 0.1), (.black, 1.0), (.blue, 10.0)] {
            let scaled = buckets.mapValues { values in
                values.map { bucket in
                    DailyTokenBucket(dayStart: bucket.dayStart, tokens: Int(Double(bucket.tokens) * multiplier),
                                     billableTokens: Int(Double(bucket.billableTokens) * multiplier),
                                     dollars: bucket.dollars.map { $0 * multiplier }, unpricedTokens: 0)
                }
            }
            let card = WeeklyUsageSnapshot.make(buckets: scaled, now: now, calendar: calendar, isDemo: true)
            for metric in WeeklyCardMetric.allCases {
                guard card.tier(for: metric) == expectedTier else { throw WeeklyCardExportError.renderingFailed }
                for format in WeeklyCardFormat.allCases {
                    let data = try WeeklyCardExporter.png(snapshot: card, format: format, signature: "@yourname", metric: metric)
                    try verify(data, format: format, tier: expectedTier)
                    try data.write(to: destination.appendingPathComponent("\(expectedTier.rawValue)-\(metric.rawValue)-\(format.rawValue).png"))
                }
            }
        }
        for (label, amount) in [("empty", 0), ("tiny", 1), ("huge", 99_999_999_999)] {
            let snapshot = WeeklyUsageSnapshot.make(buckets: [.grok: [DailyTokenBucket(dayStart: interval.start, tokens: amount, billableTokens: amount,
                                                                                      dollars: Double(amount) / 100_000, unpricedTokens: 0)]],
                                                      now: now, calendar: calendar, isDemo: true, hasPartialRecords: true)
            let data = try WeeklyCardExporter.png(snapshot: snapshot, format: .square,
                                                  signature: "@a_very_long_signature_12345678901")
            try verify(data, format: .square, tier: snapshot.tier(for: .apiValue))
            try data.write(to: destination.appendingPathComponent("edge-\(label).png"))
        }
        let differentTiers = WeeklyUsageSnapshot.make(buckets: [.grok: [DailyTokenBucket(
            dayStart: interval.start, tokens: 1_000_000_000, billableTokens: 1_000_000, dollars: 9.99, unpricedTokens: 0
        )]], now: now, calendar: calendar, isDemo: true)
        for metric in WeeklyCardMetric.allCases {
            let data = try WeeklyCardExporter.png(snapshot: differentTiers, format: .square, signature: "@yourname", metric: metric)
            try verify(data, format: .square, tier: metric == .apiValue ? .white : .blue)
            try data.write(to: destination.appendingPathComponent("metric-\(metric.rawValue).png"))
        }
        let historyStart = calendar.date(byAdding: .day, value: -800, to: calendar.startOfDay(for: now)) ?? now
        let history = Dictionary(uniqueKeysWithValues: IslandProvider.allCases.enumerated().map { providerIndex, provider in
            let records = (0...800).map { index in
                let active = index % (providerIndex + 3) != 0
                let tokens = active ? (index % 13 + 1) * 100_000 : 0
                return DailyTokenBucket(dayStart: calendar.date(byAdding: .day, value: index, to: historyStart) ?? now,
                                        tokens: tokens, billableTokens: tokens / 10,
                                        dollars: Double(tokens) / 100_000, unpricedTokens: 0)
            }
            return (provider, records)
        })
        for period in [WeeklyCardPeriod.lastThirtyDays, .lastThreeMonths, .thisYear, .allTime] {
            let card = WeeklyUsageSnapshot.make(buckets: history, period: period, now: now, calendar: calendar, isDemo: true)
            for metric in WeeklyCardMetric.allCases {
                for format in WeeklyCardFormat.allCases {
                    let data = try WeeklyCardExporter.png(snapshot: card, format: format, signature: "@yourname", metric: metric)
                    try verify(data, format: format, tier: card.tier(for: metric))
                    try data.write(to: destination.appendingPathComponent("period-\(period.rawValue)-\(metric.rawValue)-\(format.rawValue).png"))
                }
            }
        }
        let singleDay = WeeklyUsageSnapshot.make(buckets: [.codex: [DailyTokenBucket(
            dayStart: now, tokens: 1000, billableTokens: 1000, dollars: 1, unpricedTokens: 0
        )]], period: .allTime, now: now, calendar: calendar, isDemo: true)
        let singleDayPNG = try WeeklyCardExporter.png(snapshot: singleDay, format: .feed, signature: "@yourname")
        try verify(singleDayPNG, format: .feed, tier: .white)
        try singleDayPNG.write(to: destination.appendingPathComponent("period-single-day.png"))
        let data = try Data(contentsOf: destination.appendingPathComponent("black-apiValue-feed.png"))
        let share = try WeeklyCardShareContent(png: data, caption: snapshot.shareText(metric: .apiValue))
        guard share.image.representations.contains(where: { $0.pixelsWide == 1080 && $0.pixelsHigh == 1350 }),
              share.caption.contains("not a bill"), share.caption.contains("https://codexisland.com") else {
            throw WeeklyCardExportError.renderingFailed
        }
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        try WeeklyCardExporter.copyImage(data, to: clipboard)
        guard clipboard.data(forType: .png) == data, clipboard.data(forType: .tiff) != nil else {
            throw WeeklyCardExportError.clipboardFailed
        }
        print("PASS: 48 PNG renders, earned color pixels, exact output dimensions, sharing image/caption, PNG/TIFF clipboard round trip")
        print(destination.path)
    }

    static func verify(_ data: Data, format: WeeklyCardFormat, tier: WeeklyCardTier) throws {
        guard let image = NSBitmapImageRep(data: data), image.pixelsWide == 1080,
              image.pixelsHigh == Int(format.size.height * 2) else {
            throw WeeklyCardExportError.renderingFailed
        }
        guard let color = image.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else {
            throw WeeklyCardExportError.renderingFailed
        }
        let correctColor: Bool
        switch tier {
        case .white: correctColor = min(color.redComponent, color.greenComponent, color.blueComponent) > 0.8
        case .black: correctColor = max(color.redComponent, color.greenComponent, color.blueComponent) < 0.12
        case .blue: correctColor = color.blueComponent > 0.6 && color.redComponent < 0.2 && color.greenComponent < 0.35
        }
        guard correctColor else { throw WeeklyCardExportError.renderingFailed }
    }
}
