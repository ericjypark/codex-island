import SwiftUI
import Combine

@MainActor
final class IslandModel: ObservableObject {
    enum State {
        case compact
        case peek
        case expanded
    }

    /// Fired when a swipe tries to page past either end of the carousel.
    /// `PagedContent` turns it into a small rubber-band nudge so the
    /// dead-end gesture gets visible feedback instead of silently doing
    /// nothing. Fresh id per attempt so repeated over-swipes re-trigger.
    struct EdgeBump: Equatable {
        let id: UUID
        let direction: Int
    }

    @Published var state: State = .compact
    @Published var size: CGSize = .zero
    @Published var notch: NotchInfo
    @Published var edgeBump: EdgeBump?

    /// Side extension that houses each brand logo in compact state.
    let tabWidth: CGFloat = 38

    /// Per-side outboard slot that houses the peek-state percentage pill.
    /// Sized for "100% · Nd Nh" worst case at the chosen pill typography
    /// (weekly Codex windows can land at e.g. `6d 23h`). Fixed (not
    /// text-measured) so percentage updates don't jitter the silhouette
    /// width during refresh. Grown symmetrically on both sides regardless
    /// of which provider is visible — keeps the silhouette balanced over
    /// the physical notch.
    let pillSlotWidth: CGFloat = 96

    /// Visible expanded panel width.
    private let expandedWidth: CGFloat = 800

    // Mirrors measured content for hit testing; it does not constrain expanded layout.
    private var expandedHeight: CGFloat = 0

    /// Detection-pure notch from `NotchInfo.detect`. Kept separate from
    /// `notch` (which has the user's spacing override applied) so
    /// `updateNotch`'s diff guard isn't confused by override-induced
    /// width changes that originate from the store, not the screen.
    private var rawNotch: NotchInfo

    private var subs: Set<AnyCancellable> = []

    init(notch: NotchInfo) {
        self.rawNotch = notch
        self.notch = Self.applyOverride(to: notch, width: IslandSpacingStore.shared.width)
        recomputeSize()
        subscribeToSpacingStore()
    }

    func setState(_ new: State) {
        guard new != state else { return }
        state = new
        recomputeSize()
    }

    func updateNotch(_ raw: NotchInfo) {
        guard raw.width != rawNotch.width
            || raw.height != rawNotch.height
            || raw.hasNotch != rawNotch.hasNotch else { return }
        rawNotch = raw
        notch = Self.applyOverride(to: raw, width: IslandSpacingStore.shared.width)
        recomputeSize()
    }

    func updateExpandedHeight(_ height: CGFloat) {
        guard height > 0, abs(expandedHeight - height) > 0.5 else { return }
        expandedHeight = height
        if state == .expanded { recomputeSize() }
    }

    func advanceScreen() {
        let pages = ScreenPref.Screen.allCases
        let index = ScreenPref.shared.screen.pageIndex
        guard index < pages.count - 1 else {
            edgeBump = EdgeBump(id: UUID(), direction: 1)
            return
        }
        showScreen(pages[index + 1])
    }

    func rewindScreen() {
        let pages = ScreenPref.Screen.allCases
        let index = ScreenPref.shared.screen.pageIndex
        guard index > 0 else {
            edgeBump = EdgeBump(id: UUID(), direction: -1)
            return
        }
        showScreen(pages[index - 1])
    }

    func showScreen(_ screen: ScreenPref.Screen) {
        guard ScreenPref.shared.screen != screen else { return }

        withAnimation(.pageSwipe) {
            ScreenPref.shared.screen = screen
        }
    }

    /// Substitutes the user's chosen non-notch width for the detected
    /// fallback. On notched screens the raw notch is returned untouched —
    /// the override is meaningless there (you can't shrink a physical
    /// notch).
    private static func applyOverride(to raw: NotchInfo, width: CGFloat) -> NotchInfo {
        if raw.hasNotch { return raw }
        return NotchInfo(width: width, height: raw.height, hasNotch: false)
    }

    /// Re-applies the override and re-computes size whenever the user
    /// changes spacing mode. The `mode` value here is the *new* value from
    /// the closure parameter — `IslandSpacingStore.shared.mode` would be
    /// the *old* value at this point because `@Published` emits during
    /// willSet, before the property assignment lands. Reading `mode.width`
    /// off the closure parameter sidesteps the race.
    ///
    /// Wrapped in `withAnimation(.openMorph)` so the silhouette springs to
    /// its new width with the same feel as a state morph.
    private func subscribeToSpacingStore() {
        IslandSpacingStore.shared.$mode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                let new = Self.applyOverride(to: self.rawNotch, width: mode.width)
                guard new.width != self.notch.width else { return }
                withAnimation(.openMorph) {
                    self.notch = new
                    self.recomputeSize()
                }
            }
            .store(in: &subs)
    }

    private func recomputeSize() {
        switch state {
        case .compact:
            size = CGSize(
                width: notch.width + tabWidth * 2,
                height: notch.height
            )
        case .peek:
            size = CGSize(
                width: notch.width + tabWidth * 2 + pillSlotWidth * 2,
                height: notch.height
            )
        case .expanded:
            size = CGSize(
                width: expandedWidth,
                height: max(notch.height, expandedHeight)
            )
        }
    }
}
