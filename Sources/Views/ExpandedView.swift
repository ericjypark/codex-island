import SwiftUI

/// Composes the expanded panel: provider titles on top (fixed), the
/// horizontally-paged data area in the middle (usage ↔ cost ↔ overview),
/// and the footer (chip + page dots + sync status) at the bottom (fixed).
/// Only the data area slides between pages — chrome stays put.
struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(notch: model.notch)
                // The Codex reset badge's hover popover opens downward out of
                // the header; without this it renders behind PagedContent
                // (later VStack sibling → drawn on top).
                .zIndex(1)
            PagedContent(model: model)
            PanelFooter(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
