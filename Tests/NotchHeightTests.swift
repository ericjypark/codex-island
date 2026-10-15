import Foundation

/// Regression tests for NotchInfo.menuBarHeight, run by scripts/run-tests.sh
/// (bare swiftc, no XCTest — same harness pattern as ResolveUsageTests).
///
/// Locks down physical notch coverage without reintroducing menu-bar overhang
/// or changing the non-notched display and auto-hide fallbacks.
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
        expect(
            NotchInfo.menuBarHeight(safeTop: 32, visibleFrameDelta: 32, statusBarThickness: 22) == 32,
            "notched 32pt: no assumed visibleFrame gap"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 32, visibleFrameDelta: 31, statusBarThickness: 22) == 32,
            "notched 32pt: smaller visibleFrame reading does not shorten the silhouette"
        )
        // Values measured on a notched 14" MacBook Pro: menu bar occupies
        // 38pt (safeAreaInsets.top == auxiliary area height == 38), while
        // frame.maxY - visibleFrame.maxY reports 39.
        expect(
            NotchInfo.menuBarHeight(safeTop: 38, visibleFrameDelta: 39, statusBarThickness: 22) == 38,
            "notched default: physical notch height despite 1pt visibleFrame gap"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 38, visibleFrameDelta: 46, statusBarThickness: 22) == 38,
            "stale visibleFrame reading cannot exceed physical notch height"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 25, statusBarThickness: 22) == 24,
            "non-notched display: 1pt gap corrected"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 25.5, statusBarThickness: 22) == 24.5,
            "non-notched display: fractional height preserved"
        )
        expect(
            NotchInfo.menuBarHeight(safeTop: 0, visibleFrameDelta: 1, statusBarThickness: 22) == 22,
            "non-notched display: corrected zero height falls back to status bar thickness"
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
