import AppKit
import SwiftUI

@main
@MainActor
struct QuotaChartRenderHarness {
    static func main() throws {
        precondition(AppEnvironment.isDemo, "Chart QA requires isolated demo mode")
        let app = NSApplication.shared
        let preview = ProcessInfo.processInfo.environment["CHART_QA_PREVIEW"] == "1"
        app.setActivationPolicy(preview ? .regular : .prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "notes/chart-integration-20260929/renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        ProviderVisibilityStore.shared.set(.codex, at: 0)
        ProviderVisibilityStore.shared.set(.claude, at: 1)
        StylePref.shared.hasCycledStyle = true
        ScreenPref.shared.screen = .usage
        ScreenPref.shared.hasSwipedScreen = true
        let model = IslandModel(notch: NotchInfo(width: 180, height: 32, hasNotch: true))
        model.setState(.expanded)
        let scenarios = ProcessInfo.processInfo.environment["CHART_QA_PREVIEW_ONLY"] == "1"
            ? [] : ChartQAScenario.allCases
        for scenario in scenarios {
            scenario.apply()
            for style in ChartStyle.allCases {
                StylePref.shared.style = style
                let renderer = ImageRenderer(content: ChartQAPanel(model: model)
                    .transaction { $0.disablesAnimations = true })
                renderer.scale = 2
                _ = renderer.cgImage
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                if scenario.rawValue.hasPrefix("credits") {
                    precondition(UsageStore.shared.claude.visibleWindows.contains(.monthly),
                                 "Demo refresh must not overwrite the Credits fixture: \(scenario)")
                }
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { fatalError("Could not render \(style.rawValue), \(scenario.rawValue)") }
                precondition(image.width == 1600 && image.height >= 380 && image.height <= 720,
                             "Usage content must fit the 800pt panel and 360pt overlay: \(style), \(scenario), \(image.width)x\(image.height)")
                try png.write(to: output.appendingPathComponent("\(style.rawValue)-\(scenario.rawValue).png"))
            }
        }
        if !scenarios.isEmpty {
            ChartQAScenario.mixed.apply()
            StylePref.shared.style = .ring
            for style in CostStyle.allCases {
                ScreenPref.shared.screen = .cost
                CostStylePref.shared.style = style
                try render(ChartQAPage(model: model, page: .cost), to: output.appendingPathComponent("cost-\(style.rawValue).png"))
            }
            ScreenPref.shared.screen = .overview
            try render(ChartQAPage(model: model, page: .overview), to: output.appendingPathComponent("overview.png"))
            ScreenPref.shared.screen = .usage
            print("PASS: \(scenarios.count * ChartStyle.allCases.count) native chart renders including Credits layouts and bounded panel heights")
        }
        if preview {
            ChartQAScenario.creditsMixed.apply()
            StylePref.shared.style = .capacity
            ScreenPref.shared.screen = .usage
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 840, height: 380),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "CodexIsland - A layout (test data)"
            window.contentView = NSHostingView(rootView: ChartQAControls(model: model))
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            app.run()
        }
    }

    private static func render<V: View>(_ content: V, to output: URL) throws {
        let renderer = ImageRenderer(content: content.transaction { $0.disablesAnimations = true })
        renderer.scale = 2
        _ = renderer.cgImage
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { fatalError("Could not render \(output.lastPathComponent)") }
        try png.write(to: output)
    }
}

struct ChartQAPage: View {
    let model: IslandModel
    let page: ScreenPref.Screen

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(notch: model.notch)
            if page == .cost {
                CostView().padding(.vertical, IslandPanelLayout.dataVerticalInset)
            } else {
                OverviewView()
            }
            PanelFooter(model: model)
        }
        .frame(width: 800)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

enum ChartQAScenario: String, CaseIterable {
    case weekly, mixed, codex, both, unknown, zero, remaining, fiveHourOnly
    case creditsMixed, creditsRemaining, creditsUnlimited, creditsMissing, creditsError, creditsLong, creditsOnly, creditsBoth
    case creditsSwapped, creditsSingleProvider, creditsZeroLimit, creditsOverCap
    case creditsFirstFailure, creditsLongError, creditsLocalized, creditsWrappedAmount
    case creditsGrok, creditsAntigravity

    @MainActor
    func apply() {
        AppLanguageStore.shared.select(self == .creditsLocalized ? .zhHans : .en)
        ProviderVisibilityStore.shared.set(.codex, at: 0)
        ProviderVisibilityStore.shared.set(.claude, at: 1)
        if rawValue.hasPrefix("credits") {
            ProviderVisibilityStore.shared.set(.claude, at: 0)
            ProviderVisibilityStore.shared.set(.codex, at: 1)
            if self == .creditsSwapped { ProviderVisibilityStore.shared.swap() }
            if self == .creditsSingleProvider { ProviderVisibilityStore.shared.set(nil, at: 1) }
            if self == .creditsGrok { ProviderVisibilityStore.shared.set(.grok, at: 1) }
            if self == .creditsAntigravity { ProviderVisibilityStore.shared.set(.antigravity, at: 1) }
        }
        // Selection changes enqueue a demo refresh. Drain it before installing
        // this scenario so the render cannot silently capture default demo data.
        _ = ProviderConnectionStore.shared
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if self == .creditsGrok { ProviderConnectionStore.shared.refresh(.grok) }
        if self == .creditsAntigravity { ProviderConnectionStore.shared.refresh(.antigravity) }
        UsageDisplayModeStore.shared.mode = self == .remaining || self == .creditsRemaining ? .remaining : .used
        let now = Date()
        func reading(_ value: Double, _ reset: TimeInterval) -> WindowUsage {
            WindowUsage(usedPercent: value / 100, resetAt: now.addingTimeInterval(reset), error: nil)
        }
        let short: WindowUsage = self == .unknown
            ? WindowUsage(usedPercent: 0, resetAt: nil, error: "Unable to fetch usage. Check connection.")
            : reading(self == .zero ? 0 : 19, 7200)
        let codexWeek = reading(self == .zero ? 100 : 32, 3 * 86400 + 20 * 3600)
        let claudeShort = reading(self == .zero ? 0 : 14, 4 * 3600)
        let claudeWeek = reading(self == .zero ? 0 : 28, 5 * 86400 + 11 * 3600)
        let codexWindows: [UsageWindow] = self == .fiveHourOnly ? [.fiveHour]
            : [.codex, .both, .unknown, .remaining, .zero].contains(self) ? [.fiveHour, .weekly] : [.weekly]
        let claudeWindows: [UsageWindow] = self == .fiveHourOnly ? [.fiveHour]
            : [.weekly, .codex].contains(self) ? [.weekly] : [.fiveHour, .weekly]
        UsageStore.shared.codex = AppUsage(fiveHour: codexWindows.contains(.fiveHour) ? short : .unknown,
                                          weekly: codexWindows.contains(.weekly) ? codexWeek : .unknown,
                                          plan: "Pro", reportedWindows: codexWindows)
        UsageStore.shared.claude = AppUsage(fiveHour: claudeWindows.contains(.fiveHour) ? claudeShort : .unknown,
                                           weekly: claudeWindows.contains(.weekly) ? claudeWeek : .unknown,
                                           plan: "Max", reportedWindows: claudeWindows)
        UsageStore.shared.lastUpdated = now
        if rawValue.hasPrefix("credits") {
            let credit: WindowUsage
            switch self {
            case .creditsUnlimited:
                credit = WindowUsage(usedPercent: 0, resetAt: nil, error: nil, usedAmount: 1234.56, currencyCode: "USD")
            case .creditsMissing:
                credit = .unknown
            case .creditsFirstFailure:
                credit = WindowUsage(usedPercent: 0, resetAt: nil, error: "HTTP 500")
            case .creditsZeroLimit:
                credit = WindowUsage(usedPercent: 1, resetAt: nil, error: nil,
                                     usedAmount: 0, limitAmount: 0, currencyCode: "USD")
            case .creditsOverCap:
                credit = WindowUsage(usedPercent: 1.2, resetAt: nil, error: nil,
                                     usedAmount: 24, limitAmount: 20, currencyCode: "USD")
            case .creditsLongError:
                credit = WindowUsage(usedPercent: 0.4, resetAt: now.addingTimeInterval(86400),
                                     error: "The provider is temporarily unavailable. Your previous reading is retained. Check your connection and try again later.",
                                     usedAmount: 6.8, limitAmount: 17, currencyCode: "EUR")
            case .creditsWrappedAmount:
                credit = WindowUsage(usedPercent: 0.67, resetAt: nil, error: nil,
                                     usedAmount: 123456789012345.67, limitAmount: 987654321098765.43, currencyCode: "SEK")
            case .creditsError:
                credit = WindowUsage(usedPercent: 0.4, resetAt: now.addingTimeInterval(86400),
                                     error: "Unable to fetch usage. Check connection.",
                                     usedAmount: 6.8, limitAmount: 17, currencyCode: "EUR")
            case .creditsLong:
                credit = WindowUsage(usedPercent: 0.67, resetAt: now.addingTimeInterval(86400), error: nil,
                                     usedAmount: 123456789.12, limitAmount: 987654321.98, currencyCode: "SEK")
            default:
                credit = WindowUsage(usedPercent: 0, resetAt: nil, error: nil,
                                     usedAmount: 0, limitAmount: 17, currencyCode: "EUR")
            }
            UsageStore.shared.claude = AppUsage(
                fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: nil),
                weekly: reading(14, 4 * 86400 + 18 * 3600), monthly: credit, plan: "Pro",
                reportedWindows: self == .creditsOnly ? [.monthly] : [.fiveHour, .weekly, .monthly])
            UsageStore.shared.codex = AppUsage(fiveHour: .unknown,
                weekly: reading(0, 6 * 86400 + 23 * 3600),
                monthly: self == .creditsBoth ? credit : .unknown, plan: "Plus",
                reportedWindows: self == .creditsBoth ? [.weekly, .monthly] : [.weekly])
        }
    }
}

struct ChartQAPanel: View {
    let model: IslandModel
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(notch: model.notch)
            UsageView().padding(.vertical, IslandPanelLayout.dataVerticalInset)
            PanelFooter(model: model)
        }
        .frame(width: 800)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct ChartQAControls: View {
    let model: IslandModel
    @State private var scenario: ChartQAScenario = .creditsMixed
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var display = UsageDisplayModeStore.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Implemented A layout - test data, not your account").font(.headline)
                Spacer()
                Picker("Quota configuration", selection: $scenario) {
                    ForEach(ChartQAScenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 230)
                .onChange(of: scenario) { $0.apply() }
            }
            ChartQAPanel(model: model)
            HStack(spacing: 8) {
                ForEach(ChartStyle.allCases, id: \.self) { style in
                    Button(style.label) { pref.style = style }
                        .buttonStyle(.bordered)
                        .tint(pref.style == style ? .blue : .gray)
                }
                Button("Cycle") { pref.cycle() }
                Spacer()
                Picker("Display", selection: $display.mode) {
                    ForEach(UsageDisplayMode.allCases, id: \.self) { mode in Text(mode.label).tag(mode) }
                }.frame(width: 170)
            }
        }
        .padding(20)
        .preferredColorScheme(.dark)
    }
}
