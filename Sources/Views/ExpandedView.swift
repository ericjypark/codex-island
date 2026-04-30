import SwiftUI

/// Composes the expanded panel: provider titles on top (fixed), the
/// horizontally-paged data area in the middle (UsageView ↔ CostView),
/// and the footer (chip + page dots + sync status) at the bottom (fixed).
/// Only the data area slides between pages — chrome stays put.
struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(notch: model.notch)
            PagedContent()
            PanelFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
