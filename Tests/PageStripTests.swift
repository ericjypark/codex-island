import AppKit
import QuartzCore
import SwiftUI

@main
@MainActor
struct PageStripTests {
    static func main() {
        _ = NSApplication.shared
        for (maximum, lowPower, expected) in [(120, false, 120), (60, false, 60), (120, true, 30), (60, true, 30), (24, true, 24), (144, false, 120), (0, false, 60)] {
            precondition(ExpandedFrameRate.preferred(maximum: maximum, lowPower: lowPower) == expected)
        }
        let view = PageStripHost(content: Color.black)
        let size = CGSize(width: 800, height: 180)
        view.update(content: Color.black, pageIndex: 0, feedbackOffset: 0,
                    pageSize: size, lowPower: false, animated: true)
        guard let host = view.subviews.first, let layer = host.layer else { fatalError("Missing hosting layer") }
        precondition(layer.animation(forKey: "pageSlide") == nil)
        view.update(content: Color.black, pageIndex: 1, feedbackOffset: 0,
                    pageSize: size, lowPower: false, animated: true)
        guard let slide = layer.animation(forKey: "pageSlide") as? CABasicAnimation else { fatalError("Missing page animation") }
        precondition(slide.preferredFrameRateRange.preferred == 60)
        precondition(host.frame.origin.x == -800)
        view.update(content: Color.black, pageIndex: 1, feedbackOffset: 0,
                    pageSize: size, lowPower: true, animated: true)
        precondition(layer.animation(forKey: "pageSlide")?.preferredFrameRateRange.maximum == 30)
        view.update(content: Color.black, pageIndex: 2, feedbackOffset: 0,
                    pageSize: size, lowPower: true, animated: true)
        precondition(layer.animation(forKey: "pageSlide")?.preferredFrameRateRange.maximum == 30)
        precondition(host.frame.origin.x == -1600)
        view.update(content: Color.black, pageIndex: 0, feedbackOffset: 0,
                    pageSize: size, lowPower: false, animated: false)
        precondition(layer.animation(forKey: "pageSlide") == nil)
        precondition(host.frame.origin.x == 0)
        print("PASS refresh policy, initial placement, page animation, low-power cap, and nonanimated placement")
    }
}
