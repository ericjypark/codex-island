import Foundation

/// Regression tests for NotchInfo.menuBarHeight, run by scripts/run-tests.sh
/// (bare swiftc, no XCTest — same harness pattern as ResolveUsageTests).
///
/// Locks down the menu-bar overhang fix: NSScreen.visibleFrame.maxY sits 1pt
/// below the menu bar's bottom edge, so the raw frame/visibleFrame delta made
/// the compact silhouette 1pt taller than the bar (and stale readings made it
/// arbitrarily worse), dipping the pill's rounded bottom into app content —
/// and, because the hit rect tracks the silhouette, stealing hover/clicks
/// from the app underneath.
@main
struct NotchHeightTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS \(label)")
        } else {
            print("FAIL \(label)")
            failures += 1
        }
    }

    static func main() {
        // Values measured on a notched 14" MacBook Pro: menu bar occupies
        // 38pt (safeAreaInsets.top == auxiliary area height == 38), while
        // frame.maxY - visibleFrame.maxY reports 39.
        expect(
            NotchInfo.menuBarHeight(safeTop: 38, visibleFrameDelta: 39, statusBarThickness: 22) == 38,
            "notched default: 1pt visibleFrame gap corrected"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 38, visibleFrameDelta: 46, statusBarThickness: 22) == 38,
            "stale visibleFrame reading clamped to physical notch height"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 25, statusBarThickness: 22) == 24,
            "non-notched display: 1pt gap corrected"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 38, visibleFrameDelta: 0, statusBarThickness: 22) == 38,
            "auto-hide menu bar on notched screen: physical notch height"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 0, statusBarThickness: 22) == 22,
            "auto-hide menu bar, non-notched: status bar thickness"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 0, statusBarThickness: 0) == 24,
            "nothing measurable: 24pt default"
        )

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("all NotchHeightTests passed")
    }
}
