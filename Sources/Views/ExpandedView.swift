import SwiftUI

/// Content shown when the island is expanded. Filled in by the panel
/// layout commit; for now it's an empty container so the morph mechanic
/// works end-to-end before we wire up the charts.
struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Color.clear
    }
}
