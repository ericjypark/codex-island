import AppKit
import SwiftUI

@main
@MainActor
struct RenderMacReference {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        UserDefaults.standard.set(["codex", "antigravity"], forKey: ProviderVisibilityStore.selectionKey)
        ScreenPref.shared.hasSwipedScreen = true
        UsageStore.shared.refresh()
        CostStore.shared.refresh()
        if CommandLine.arguments.contains("--settings-only") {
            UserDefaults.standard.set("providers", forKey: "Settings.activeTab")
            try save(SettingsView().frame(width: 480, height: 720), name: "settings-providers", to: destination)
            try save(SettingsView().frame(width: 440, height: 560), name: "settings-providers-narrow", to: destination)
            print("Rendered Providers directly from the current Mac SwiftUI source.")
            return
        }
        StylePref.shared.hasCycledStyle = true
        CostStylePref.shared.hasCycledStyle = true
        let notch = NotchInfo(width: 220, height: 38, hasNotch: true)
        let model = IslandModel(notch: notch)
        model.setState(.expanded)
        for style in ChartStyle.allCases {
            ScreenPref.shared.screen = .usage
            StylePref.shared.style = style
            try save(ExpandedView(model: model).frame(width: 800).background(.black).clipShape(IslandShape()),
                     name: "usage-\(style.rawValue)", to: destination)
        }
        ScreenPref.shared.screen = .cost
        for style in CostStyle.allCases {
            CostStylePref.shared.style = style
            try save(ExpandedView(model: model).frame(width: 800).background(.black).clipShape(IslandShape()),
                     name: "cost-\(style.rawValue)", to: destination)
        }
        ScreenPref.shared.screen = .overview
        try save(ExpandedView(model: model).frame(width: 800).background(.black).clipShape(IslandShape()),
                 name: "overview", to: destination)
        setenv("WINDOWS_REFERENCE_DAY", ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())), 1)
        try save(ExpandedView(model: model).frame(width: 800).background(.black).clipShape(IslandShape()),
                 name: "overview-detail", to: destination)
        unsetenv("WINDOWS_REFERENCE_DAY")
        for tab in ["general", "display", "providers"] {
            UserDefaults.standard.set(tab, forKey: "Settings.activeTab")
            try save(SettingsView().frame(width: 480, height: 720), name: "settings-\(tab)", to: destination)
        }
        let cardBuckets = Dictionary(uniqueKeysWithValues: IslandProvider.allCases.map { ($0, CostStore.shared.cost(for: $0).dailyTokens) })
        let cardSnapshot = WeeklyUsageSnapshot.make(buckets: cardBuckets, isDemo: true)
        for format in WeeklyCardFormat.allCases {
            for metric in WeeklyCardMetric.allCases {
                try save(WeeklyUsageCard(snapshot: cardSnapshot, format: format, metric: metric),
                         name: "card-\(format.rawValue)-\(metric.rawValue)", to: destination)
            }
        }
        try save(WeeklyCardStudio().frame(width: 900, height: 740), name: "card-studio", to: destination)
        var commands: [[String: Any]] = []
        IslandShape().path(in: CGRect(x: 0, y: 0, width: 800, height: 226)).forEach { element in
            switch element {
            case .move(to: let p): commands.append(["type": "M", "points": [p.x, p.y]])
            case .line(to: let p): commands.append(["type": "L", "points": [p.x, p.y]])
            case .quadCurve(to: let p, control: let c): commands.append(["type": "Q", "points": [c.x, c.y, p.x, p.y]])
            case .curve(to: let p, control1: let c1, control2: let c2): commands.append(["type": "C", "points": [c1.x, c1.y, c2.x, c2.y, p.x, p.y]])
            case .closeSubpath: commands.append(["type": "Z"])
            }
        }
        var providers: [[String: Any]] = []
        for provider in IslandProvider.allCases {
            let cost = CostStore.shared.cost(for: provider)
            var limits: [[String: Any]] = []
            let plan: String?
            if provider.usesLegacyUsage {
                let usage = provider == .claude ? UsageStore.shared.claude : UsageStore.shared.codex
                plan = usage.plan
                for (index, kind) in usage.visibleWindows.enumerated() {
                    let window = usage.window(kind)
                    limits.append(["label": kind == .fiveHour ? "5h" : "week",
                                   "used": window.hasReading ? window.usedPercent * 100 : NSNull(),
                                   "resetSeconds": window.resetAt?.timeIntervalSinceNow ?? 0,
                                   "seed": (provider == .claude ? 1 : 3) + index])
                }
            } else {
                ProviderConnectionStore.shared.refresh(provider, manually: true)
                let snapshot = ProviderConnectionStore.shared.snapshot(provider)
                plan = snapshot.plan
                for (index, limit) in ProviderConnectionStore.shared.limits(provider).enumerated() {
                    limits.append(["label": limit.label, "used": limit.usedFraction.map { $0 * 100 } as Any? ?? NSNull(),
                                   "resetSeconds": limit.resetAt?.timeIntervalSinceNow ?? 0,
                                   "seed": (provider == .grok ? 5 : 7) + index])
                }
            }
            func costData(_ value: CostWindow) -> [String: Any] {
                ["dollars": value.dollars, "tokens": value.tokens, "billableTokens": value.billableTokens,
                 "series": value.series, "label": value.label]
            }
            providers.append(["id": provider.rawValue, "name": provider.name,
                              "plan": provider.planDisplayName(plan) ?? "", "limits": limits,
                              "days": cost.dailyTokens.map { ["date": ISO8601DateFormatter().string(from: $0.dayStart),
                                   "tokens": $0.tokens, "billableTokens": $0.billableTokens, "dollars": $0.dollars as Any? ?? NSNull()] },
                              "today": costData(cost.today), "month": costData(cost.month),
                              "models": cost.weekByModel.map { row -> [String: Any] in
                                  let recent = cost.recentByModel.first { $0.model == row.model }
                                  return ["id": row.model, "name": row.displayName, "weekTokens": row.tokens,
                                          "weekDollars": row.dollars, "recentTokens": recent?.tokens ?? 0,
                                          "recentDollars": recent?.dollars ?? 0]
                              }])
        }
        let fixture: [String: Any] = ["source": "CodexIsland SwiftUI demo", "date": ISO8601DateFormatter().string(from: Date()),
                                       "shape": commands, "providers": providers,
                                       "proportionalFont": NSFont.systemFont(ofSize: 13, weight: .semibold).fontName,
                                       "monospacedFont": NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold).fontName]
        try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("fixture.json"))
        print("Rendered Mac reference directly from the existing SwiftUI source: \(destination.path)")
    }

    static func save<V: View>(_ view: V, name: String, to directory: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let fitting = host.fittingSize
        host.frame = NSRect(origin: .zero, size: fitting)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "MacReference", code: 1, userInfo: [NSLocalizedDescriptionKey: name])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MacReference", code: 2, userInfo: [NSLocalizedDescriptionKey: name])
        }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}
