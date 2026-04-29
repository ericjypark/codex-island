import SwiftUI

struct IslandRootView: View {
    let notch: NotchInfo

    /// Visible side extensions housing the brand logos in compact state.
    static let tabWidth: CGFloat = 38

    private var compactSize: CGSize {
        CGSize(width: notch.width + Self.tabWidth * 2, height: notch.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            IslandShape()
                .fill(.black)
                .frame(width: compactSize.width, height: compactSize.height)
                .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
