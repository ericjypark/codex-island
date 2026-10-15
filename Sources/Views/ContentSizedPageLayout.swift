import SwiftUI

struct ContentSizedPageLayout: Layout {
    let selectedPage: Int
    var position: CGFloat
    var feedbackOffset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(position, feedbackOffset) }
        set {
            position = newValue.first
            feedbackOffset = newValue.second
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.indices.contains(selectedPage) else { return .zero }
        let width = proposal.width ?? 800
        // The target page owns height even while horizontal position is between pages.
        let content = subviews[selectedPage].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: content.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + (CGFloat(index) - position) * bounds.width + feedbackOffset,
                            y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}
