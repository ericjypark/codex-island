import AppKit
import SwiftUI

// Run only through scripts/benchmark-rendering.sh: demo data and a separate
// bundle isolate the benchmark from credentials, polling, and app preferences.
@main
@MainActor
struct RenderingBenchmark {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ScreenPref.shared.screen = .usage
        ScreenPref.shared.hasSwipedScreen = true
        UsageStore.shared.refresh()
        StylePref.shared.style = .ring
        CostStylePref.shared.style = .dollar
        let model = IslandModel(notch: NotchInfo(width: 180, height: 32, hasNotch: false))
        model.setState(.expanded)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 840, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: BenchmarkPanel(model: model))
        window.orderFrontRegardless()
        if ProcessInfo.processInfo.environment["RENDER_BENCHMARK_PREVIEW"] == "1" {
            model.showScreen(.overview)
            app.run()
            return
        }
        var intervals: [Double] = []
        var previous = ProcessInfo.processInfo.systemUptime
        let start = previous
        var step = -1
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - start
                if elapsed > 2 { intervals.append((now - previous) * 1000) }
                previous = now
                let nextStep = Int(elapsed / 0.7)
                if nextStep != step {
                    step = nextStep
                    model.showScreen(ScreenPref.Screen.allCases[nextStep % 3])
                    StylePref.shared.cycle()
                    CostStylePref.shared.cycle()
                }
                if elapsed >= 12 {
                    intervals.sort()
                    let p95 = intervals[Int(Double(intervals.count - 1) * 0.95)]
                    let p99 = intervals[Int(Double(intervals.count - 1) * 0.99)]
                    print(String(format: "main-loop samples=%d p95=%.2fms p99=%.2fms max=%.2fms gaps>25ms=%d",
                                 intervals.count, p95, p99, intervals.last ?? 0,
                                 intervals.filter { $0 > 25 }.count))
                    exit(EXIT_SUCCESS)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
        timer.invalidate()
        window.orderOut(nil)
    }
}

private struct BenchmarkPanel: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        ExpandedView(model: model)
            .frame(width: model.size.width)
            .background(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
