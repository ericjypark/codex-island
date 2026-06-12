import SwiftUI
import Combine

@MainActor
final class IslandModel: ObservableObject {
    enum State {
        case compact
        case peek
        case expanded
    }

    @Published var state: State = .compact
    @Published var size: CGSize = .zero
    @Published var notch: NotchInfo

    /// Maximum side extension for the brand logo tab in compact state.
    private let maxTabWidth: CGFloat = 38
    /// Maximum per-side outboard slot for the peek-state percentage pill.
    private let maxPillSlotWidth: CGFloat = 78
    /// Safety gap (pt) between our outermost edge and the nearest menu item.
    private let sideMargin: CGFloat = 8

    /// Actual tab width, clamped to the space available beside the notch
    /// before menu items begin (macOS 27+). Falls back to maxTabWidth when
    /// there is no constraint (older macOS / non-notch screens).
    var tabWidth: CGFloat {
        let available = notch.sideSpace == .infinity ? maxTabWidth : max(0, notch.sideSpace - sideMargin)
        return min(maxTabWidth, available)
    }

    /// Actual peek pill slot width, clamped to whatever space remains after
    /// the tab and safety margin are accounted for.
    var pillSlotWidth: CGFloat {
        let available = notch.sideSpace == .infinity ? maxPillSlotWidth : max(0, notch.sideSpace - sideMargin - tabWidth)
        return min(maxPillSlotWidth, available)
    }

    /// True when compact-state logo tabs are suppressed because menu items are
    /// too close. Logos reappear as soon as the user hovers (peek state always
    /// expands to full width regardless of this constraint).
    var compactLogosHidden: Bool { tabWidth < maxTabWidth }

    /// Visible expanded panel width.
    private let expandedWidth: CGFloat = 800

    /// Visible expanded panel content height. The shape sits flush with the
    /// top of the screen, so we add notch.height of "filler" so visible
    /// content sits BELOW the notch line.
    private let expandedBaseContentHeight: CGFloat = 188

    /// Overview needs room for the full-year contribution grid. Keep this
    /// page-specific so usage/cost preserve their compact original height.
    private let overviewBaseContentHeight: CGFloat = 244

    /// Extra room for the overview's selected-day details. Kept below the
    /// fixed host window height on standard notch/menu-bar sizes.
    private let overviewDetailContentHeight: CGFloat = 52

    /// Detection-pure notch from `NotchInfo.detect`. Kept separate from
    /// `notch` (which has the user's spacing override applied) so
    /// `updateNotch`'s diff guard isn't confused by override-induced
    /// width changes that originate from the store, not the screen.
    private var rawNotch: NotchInfo
    private var activeScreen = ScreenPref.shared.screen
    private var overviewDayDetailVisible = false

    private var subs: Set<AnyCancellable> = []

    init(notch: NotchInfo) {
        self.rawNotch = notch
        self.notch = Self.applyOverride(to: notch, width: IslandSpacingStore.shared.width)
        recomputeSize()
        subscribeToSpacingStore()
        subscribeToScreenPref()
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

    func setOverviewDayDetailVisible(_ visible: Bool) {
        guard overviewDayDetailVisible != visible else { return }
        overviewDayDetailVisible = visible
        withAnimation(visible ? .detailExpand : .detailCollapse) {
            recomputeSize()
        }
    }

    func advanceScreen() {
        let pages = ScreenPref.Screen.allCases
        let index = ScreenPref.shared.screen.pageIndex
        guard index < pages.count - 1 else { return }
        showScreen(pages[index + 1])
    }

    func rewindScreen() {
        let pages = ScreenPref.Screen.allCases
        let index = ScreenPref.shared.screen.pageIndex
        guard index > 0 else { return }
        showScreen(pages[index - 1])
    }

    func showScreen(_ screen: ScreenPref.Screen) {
        guard ScreenPref.shared.screen != screen else { return }

        if shouldCollapseDetailBeforeShowing(screen) {
            withAnimation(.pageSwipe) {
                overviewDayDetailVisible = false
                activeScreen = screen
                ScreenPref.shared.screen = screen
                recomputeSize()
            }
            return
        }

        activeScreen = screen
        ScreenPref.shared.screen = screen
    }

    /// Substitutes the user's chosen non-notch width for the detected
    /// fallback. On notched screens the raw notch is returned untouched —
    /// the override is meaningless there (you can't shrink a physical
    /// notch).
    private static func applyOverride(to raw: NotchInfo, width: CGFloat) -> NotchInfo {
        if raw.hasNotch { return raw }
        return NotchInfo(width: width, height: raw.height, hasNotch: false, sideSpace: .infinity)
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

    private func subscribeToScreenPref() {
        ScreenPref.shared.$screen
            .dropFirst()
            .sink { [weak self] screen in
                guard let self, self.state == .expanded else { return }
                let wasShowingOverviewDetail = self.overviewDayDetailVisible
                self.activeScreen = screen
                if screen != .overview {
                    self.overviewDayDetailVisible = false
                }
                withAnimation(wasShowingOverviewDetail ? .pageSwipe : .detailCollapse) {
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
            // Always expand to full peek width on hover even when compact is
            // constrained — the user is actively interacting, brief menu
            // overlap is acceptable and logos/pills must always be reachable.
            size = CGSize(
                width: notch.width + maxTabWidth * 2 + maxPillSlotWidth * 2,
                height: notch.height
            )
        case .expanded:
            size = CGSize(
                width: expandedWidth,
                height: expandedContentHeight + notch.height
            )
        }
    }

    private var expandedContentHeight: CGFloat {
        let baseHeight = activeScreen == .overview
            ? overviewBaseContentHeight
            : expandedBaseContentHeight
        let detailHeight = activeScreen == .overview && overviewDayDetailVisible
            ? overviewDetailContentHeight
            : 0
        return baseHeight + detailHeight
    }

    private func shouldCollapseDetailBeforeShowing(_ screen: ScreenPref.Screen) -> Bool {
        activeScreen == .overview
            && screen != .overview
            && overviewDayDetailVisible
    }
}
