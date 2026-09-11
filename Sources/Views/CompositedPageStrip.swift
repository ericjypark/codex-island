import AppKit
import QuartzCore
import SwiftUI

// Animate the hosting layer so horizontal movement does not invalidate SwiftUI layout per frame.
struct CompositedPageStrip<Content: View>: NSViewRepresentable {
    let pageIndex: Int
    let feedbackOffset: CGFloat
    let pageSize: CGSize
    let lowPower: Bool
    let content: Content

    func makeNSView(context: Context) -> PageStripHost<Content> {
        PageStripHost(content: content)
    }

    func updateNSView(_ view: PageStripHost<Content>, context: Context) {
        view.update(content: content, pageIndex: pageIndex, feedbackOffset: feedbackOffset, pageSize: pageSize,
                    lowPower: lowPower, animated: !context.transaction.disablesAnimations)
    }
}

final class PageStripHost<Content: View>: NSView {
    private let host: PageStripHostingView<Content>
    private var previousPage: Int?
    private var previousFeedback: CGFloat = 0
    private var lowPower = false

    override var isFlipped: Bool { true }

    init(content: Content) {
        host = PageStripHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        host.wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
    }

    required init?(coder: NSCoder) { nil }

    func update(content: Content, pageIndex: Int, feedbackOffset: CGFloat, pageSize: CGSize,
                lowPower: Bool, animated: Bool) {
        let changed = previousPage != nil && (previousPage != pageIndex || previousFeedback != feedbackOffset)
        let offset = -pageSize.width * CGFloat(pageIndex) + feedbackOffset
        let powerChanged = self.lowPower != lowPower
        self.lowPower = lowPower
        let from = host.layer?.presentation()?.position.x ?? host.layer?.position.x
        host.rootView = content
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = CGRect(x: offset, y: 0, width: pageSize.width * 3, height: pageSize.height)
        CATransaction.commit()
        previousPage = pageIndex
        previousFeedback = feedbackOffset

        guard let layer = host.layer else { return }
        let fps = Float(ExpandedFrameRate.preferred(
            maximum: window?.screen?.maximumFramesPerSecond ?? 60, lowPower: lowPower))
        let range = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        if (changed || powerChanged), animated, let from, from != layer.position.x {
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = from
            animation.toValue = layer.position.x
            animation.duration = 0.36
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.82, 0.25, 1)
            animation.preferredFrameRateRange = range
            layer.add(animation, forKey: "pageSlide")
        } else if !animated {
            layer.removeAnimation(forKey: "pageSlide")
        } else if powerChanged, let animation = layer.animation(forKey: "pageSlide")?.copy() as? CAAnimation {
            animation.preferredFrameRateRange = range
            layer.add(animation, forKey: "pageSlide")
        }
    }
}

private final class PageStripHostingView<Content: View>: NSHostingView<Content> {
    override func scrollWheel(with event: NSEvent) {
        // A nested hosting view must preserve the island's trackpad paging route.
        var ancestor = superview
        while let view = ancestor {
            if let island = view as? IslandHostingView {
                island.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
        super.scrollWheel(with: event)
    }
}
