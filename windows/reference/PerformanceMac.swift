import AppKit
import SwiftUI
import Darwin

@main
@MainActor
struct PerformanceMac {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await runScenarios() }
            catch { fputs("Mac performance reference failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            NSApplication.shared.terminate(nil)
        }
        NSApplication.shared.run()
    }

    private static func runScenarios() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UserDefaults.standard.set(["codex", "antigravity"], forKey: ProviderVisibilityStore.selectionKey)
        ScreenPref.shared.hasSwipedScreen = true
        StylePref.shared.hasCycledStyle = true
        CostStylePref.shared.hasCycledStyle = true
        StylePref.shared.style = .spark
        CostStylePref.shared.style = .dollar
        UsageStore.shared.refresh()
        CostStore.shared.refresh()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        defer { window.orderOut(nil); window.close() }
        let scenarios: [(String, IslandModel.State, ScreenPref.Screen, Bool, Bool, Bool)] = [
            ("compact-rest", .compact, .usage, false, false, false),
            ("peek-hover", .peek, .usage, true, false, false),
            ("usage-settled", .expanded, .usage, true, false, false),
            ("cost-settled", .expanded, .cost, true, false, false),
            ("overview-settled", .expanded, .overview, true, false, false),
            ("always-visible-rest", .peek, .usage, false, true, false),
            ("low-power-rest", .peek, .usage, false, true, true)
        ]
        var results: [[String: Any]] = []
        for (name, state, page, hover, always, lowPower) in scenarios {
            AlwaysShowUsageStore.shared.enabled = always
            LowPowerModeStore.shared.enabled = lowPower
            ScreenPref.shared.screen = page
            let model = IslandModel(notch: NotchInfo(width: 220, height: 38, hasNotch: true))
            model.setState(state)
            let root = IslandRootView(model: model, benchmarkHovering: hover,
                                      benchmarkVisible: state == .expanded, benchmarkPills: state == .peek)
            let host = NSHostingView(rootView: root.environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 420)
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .seconds(1.5))
            let before = processSeconds()
            let start = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(6))
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let cpu = processSeconds() - before
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let result: [String: Any] = ["scenario": name, "elapsedMs": elapsed * 1000,
                "cpuOneCorePercent": cpu / elapsed * 100,
                "peakResidentMB": Double(usage.ru_maxrss) / 1048576,
                "scale": window.backingScaleFactor, "maximumRefreshHz": window.screen?.maximumFramesPerSecond ?? 0,
                "systemLowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "panelWidth": model.size.width, "panelHeight": model.size.height,
                "scope": "real IslandRootView and effects, fixture-initialized hover and visibility, optimized separate demo app"]
            results.append(result)
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("performance-mac.json"), options: .atomic)
            print(String(format: "%@: %.2f%% of one core", name, cpu / elapsed * 100))
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: output.appendingPathComponent("perf-mac-\(name).png"))
            }
        }
    }

    private static func processSeconds() -> Double {
        var value = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }
}
