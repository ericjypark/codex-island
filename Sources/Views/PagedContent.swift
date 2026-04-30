import SwiftUI

/// Two-page horizontal carousel: the usage data row (page 0) and the cost
/// data row (page 1). Both pages render at the full content width; the
/// HStack is twice that width and slides via `.offset` based on
/// `ScreenPref.screen`. Animation uses the same spring as the expanded-
/// state shape morph for cohesion.
///
/// Only the data row swipes — `PanelHeader` and `PanelFooter` are mounted
/// outside this view so they stay fixed across page changes.
struct PagedContent: View {
    @ObservedObject private var screenPref = ScreenPref.shared

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            HStack(spacing: 0) {
                UsageView()
                    .frame(width: pageWidth)
                CostView()
                    .frame(width: pageWidth)
            }
            .frame(width: pageWidth, alignment: .leading)
            .offset(x: screenPref.screen == .usage ? 0 : -pageWidth)
            .animation(.openMorph, value: screenPref.screen)
            .clipped()
        }
    }
}
