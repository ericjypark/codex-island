import SwiftUI

/// Two-page horizontal carousel: UsageView (page 0) and CostView (page 1).
/// Both pages render at the full content width; the HStack is twice that
/// width and slides via .offset based on `ScreenPref.screen`. Animation uses
/// the same spring as the expanded-state shape morph for cohesion.
struct PagedContent: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var screenPref = ScreenPref.shared

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            HStack(spacing: 0) {
                UsageView(notch: model.notch)
                    .frame(width: pageWidth)
                CostView(notch: model.notch)
                    .frame(width: pageWidth)
            }
            .frame(width: pageWidth, alignment: .leading)
            .offset(x: screenPref.screen == .usage ? 0 : -pageWidth)
            .animation(.openMorph, value: screenPref.screen)
            .clipped()
        }
    }
}
