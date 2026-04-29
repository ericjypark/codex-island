import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    /// Visible side extensions housing the brand logos in compact state.
    static let tabWidth: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            IslandShape()
                .fill(.black)
                .frame(width: model.size.width, height: model.size.height)
                .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
