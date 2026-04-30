import SwiftUI

struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        PagedContent(model: model)
    }
}
