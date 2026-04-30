import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    enum State {
        case compact
        case expanded
    }

    @Published var state: State = .compact
    @Published var size: CGSize = .zero
    @Published var notch: NotchInfo

    /// Side extension that houses each brand logo in compact state.
    let tabWidth: CGFloat = 38

    /// Visible expanded panel width.
    private let expandedWidth: CGFloat = 720

    /// Visible expanded panel content height. The shape sits flush with the
    /// top of the screen, so we add notch.height of "filler" so visible
    /// content sits BELOW the notch line.
    private let expandedContentHeight: CGFloat = 172

    init(notch: NotchInfo) {
        self.notch = notch
        recomputeSize()
    }

    func setState(_ new: State) {
        guard new != state else { return }
        state = new
        recomputeSize()
    }

    func updateNotch(_ new: NotchInfo) {
        guard new.width != notch.width || new.height != notch.height || new.hasNotch != notch.hasNotch else { return }
        notch = new
        recomputeSize()
    }

    private func recomputeSize() {
        switch state {
        case .compact:
            size = CGSize(
                width: notch.width + tabWidth * 2,
                height: notch.height
            )
        case .expanded:
            size = CGSize(
                width: expandedWidth,
                height: expandedContentHeight + notch.height
            )
        }
    }
}
