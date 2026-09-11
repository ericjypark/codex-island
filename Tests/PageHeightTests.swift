import AppKit
import SwiftUI

@main
@MainActor
struct PageHeightTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ScreenPref.shared.hasSwipedScreen = true
        let model = IslandModel(notch: NotchInfo(width: 180, height: 32, hasNotch: false))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 900, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = IslandHostingView(rootView: IslandRootView(model: model), model: model)
        window.orderFrontRegardless()
        Task { @MainActor in
            model.setState(.expanded)
            var heights: [ScreenPref.Screen: CGFloat] = [:]
            for page in ScreenPref.Screen.allCases {
                model.showScreen(page)
                try? await Task.sleep(nanoseconds: 700_000_000)
                heights[page] = model.size.height
                print("Measured \(page): \(model.size.height)")
            }
            precondition((heights[.overview] ?? 0) > (heights[.cost] ?? 0))
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
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    precondition(abs(model.size.height - (heights[destination] ?? 0)) < 1,
                                 "Opening interrupted by navigation left the wrong height")
                }
            }
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
