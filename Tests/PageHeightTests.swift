import AppKit
import SwiftUI

@main
@MainActor
struct PageHeightTests {
    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ScreenPref.shared.hasSwipedScreen = true
        let model = IslandModel(notch: NotchInfo(width: 180, height: 32, hasNotch: false))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 900, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        // Height transitions are driven by this test, not the real cursor.
        window.ignoresMouseEvents = true
        window.contentView = IslandHostingView(rootView: IslandRootView(
            model: model, tracksHover: false, initialContentVisible: true), model: model)
        window.orderFrontRegardless()
        Task { @MainActor in
            @MainActor func settleLayout() async {
                try? await Task.sleep(nanoseconds: 700_000_000)
                // Native test windows may not be redrawn while unfocused.
                // Flush layout before reading the geometry preference.
                window.contentView?.needsLayout = true
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            model.setState(.expanded)
            var heights: [ScreenPref.Screen: CGFloat] = [:]
            for page in ScreenPref.Screen.allCases {
                model.showScreen(page)
                await settleLayout()
                heights[page] = model.size.height
                print("Measured \(page): \(model.size.height)")
            }
            precondition((heights[.overview] ?? 0) > (heights[.cost] ?? 0),
                         "Overview must be taller than Cost in the fixture")
            for delay: UInt64 in [0, 5_000_000, 20_000_000, 80_000_000] {
                for destination in ScreenPref.Screen.allCases {
                    withAnimation(.closeMorph) { model.setState(.compact) }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation(.openMorph) { model.setState(.expanded) }
                    try? await Task.sleep(nanoseconds: delay)
                    for page in [ScreenPref.Screen.cost, .usage, .cost, .overview, destination] {
                        model.showScreen(page)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    await settleLayout()
                    print("Navigation \(delay)ns -> \(destination): expected \(heights[destination] ?? 0), measured \(model.size.height), state \(model.state)")
                    precondition(abs(model.size.height - (heights[destination] ?? 0)) < 1,
                                 "Opening interrupted by navigation left the wrong height")
                }
            }
            ProviderVisibilityStore.shared.set(.claude, at: 0)
            ProviderVisibilityStore.shared.set(.codex, at: 1)
            let measured = WindowUsage(usedPercent: 0.14, resetAt: nil, error: nil)
            let withoutCredits = AppUsage(fiveHour: measured, weekly: measured,
                                         reportedWindows: [.fiveHour, .weekly])
            UsageStore.shared.claude = withoutCredits
            UsageStore.shared.codex = AppUsage(fiveHour: .unknown, weekly: measured, reportedWindows: [.weekly])
            model.showScreen(.usage)
            await settleLayout()
            let quotaHeight = model.size.height
            print("Quota baseline: \(quotaHeight)")
            precondition(abs(quotaHeight - (heights[.usage] ?? 0)) < 1,
                         "Usage must settle before measuring the Credits height delta")
            let withCredits = AppUsage(fiveHour: measured, weekly: measured,
                monthly: WindowUsage(usedPercent: 0.4, resetAt: nil,
                                     error: "Unable to fetch usage. Check connection.",
                                     usedAmount: 6.8, limitAmount: 17, currencyCode: "EUR"),
                reportedWindows: [.fiveHour, .weekly, .monthly])
            UsageStore.shared.claude = withCredits
            await settleLayout()
            let creditsHeight = model.size.height
            print("Credits height: \(creditsHeight)")
            precondition(model.size.height > quotaHeight + 30,
                         "Credits summary and its error must contribute to the real panel height")
            precondition(model.size.height <= IslandWindowController.windowSize.height,
                         "Credits summary must fit the overlay window")
            UsageStore.shared.claude = withoutCredits
            await settleLayout()
            precondition(abs(model.size.height - quotaHeight) < 1,
                         "Removing Credits must release its space")
            print("PASS Credits addition/removal resizes the real island and hit-test model: \(quotaHeight) -> \(creditsHeight) -> \(model.size.height)")

            // Publishing provider data and navigating in the same turn used to
            // update the footer while leaving the previous page body mounted.
            for repetition in 1...2 {
                for hasCredits in [false, true] {
                    for destination in ScreenPref.Screen.allCases {
                        model.showScreen(destination == .overview ? .cost : .overview)
                        await settleLayout()
                        UsageStore.shared.claude = hasCredits ? withCredits : withoutCredits
                        UsageStore.shared.codex = AppUsage(fiveHour: .unknown, weekly: measured,
                                                          reportedWindows: [.weekly])
                        model.showScreen(destination)
                        await settleLayout()
                        let expected = destination == .usage
                            ? (hasCredits ? creditsHeight : quotaHeight)
                            : (heights[destination] ?? 0)
                        print("Combined update \(repetition), Credits=\(hasCredits), \(destination): expected \(expected), measured \(model.size.height)")
                        precondition(ScreenPref.shared.screen == destination,
                                     "Navigation must commit the requested page")
                        precondition(abs(model.size.height - expected) < 1,
                                     "Provider publication and navigation left the previous page visible")
                    }
                }
            }
            print("PASS all 12 simultaneous provider-update/navigation sequences")

            let fixture = NSHostingView(rootView: ContentSizedPageLayout(selectedPage: 1, position: 0.3) {
                Color.red.frame(height: 80)
                Color.blue.frame(height: 217)
                Color.green.frame(height: 350)
            }.frame(width: 800).fixedSize(horizontal: false, vertical: true))
            window.contentView = fixture
            try? await Task.sleep(nanoseconds: 100_000_000)
            precondition(abs(fixture.fittingSize.height - 217) < 1,
                         "Selected content must own height during an interrupted slide")
            print("PASS intrinsic sizing and all 12 immediate-open navigation sequences")
            exit(0)
        }
        app.run()
    }
}
