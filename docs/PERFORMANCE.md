# Rendering performance

## Fullscreen visibility

`FullscreenStore` hides the island in the current native fullscreen Space on
the island's selected display. `MacIsland.hideInFullscreen` defaults to true
and has an independent General setting. Native fullscreen video and Split View
are covered; ordinary maximized windows and fullscreen apps in inactive Spaces
are not fullscreen suppressors. Fullscreen on another display does not hide the
island. A shared Space (when displays do not have separate Spaces) applies to all
displays. Custom borderless modes that do not create a native fullscreen Space
are not detected by this setting.

Apple documents `NSApplication.currentSystemPresentationOptions` as observable,
but it reported no fullscreen flag while Firefox occupied a native fullscreen
Space on the tested macOS 26.6 system. `FullscreenSpaceReader` instead optionally
resolves `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces` at runtime. These
are undocumented, read-only WindowServer interfaces. It inspects only the target
display's `Current Space` type (0 for desktop, 4 for fullscreen), not other
Spaces or window bounds. Missing symbols, display mappings, or unfamiliar
payloads fail open. No screen capture, Accessibility access, browser data,
private framework linking, or Space mutation is involved.

The store reads at startup and on workspace Space/app/wake and display-change
notifications, with explicit refreshes on target selection and unlock. There is
no polling timer. The combined visibility subscription seeds all suppressors
before the first display; hiding and restoring reuse the input/focus safeguards
below. Fullscreen, Game Mode and lock are independent: all enabled suppressors
must clear before restoration. macOS can keep Game Mode active briefly after
leaving a game, delaying restoration even on the desktop.

`Tests/FullscreenTests.swift` covers display mapping, malformed snapshots,
inactive fullscreen Spaces, every lock/game/fullscreen preference combination,
input gating, preference persistence, startup and notification refreshes using
private test notification centers. Fixtures are not proof of live transitions.
Live acceptance additionally checks native browser video entry/exit and Space
switches, startup in fullscreen, selected-monitor changes, and preserved focus.

## Game Mode visibility

`GameModeStore` reads the Boolean state on the Darwin notification
`com.apple.system.console_mode_changed`, emitted by macOS `gamepolicyd`.
This is an undocumented OS signal, not a supported Game Mode API. It was
observed active on macOS 26.6 during a native full-screen game; do not infer
support on every OS release from successful notification registration alone.
Unknown states and read failures leave the island visible. No screen capture,
Accessibility permission, private framework linking, or polling is needed.

`MacIsland.hideDuringGameMode` defaults to true and can be disabled in General
settings. `IslandWindowController` combines Game Mode with its existing lock
state, so ending a game cannot reveal a locked session and unlocking cannot
reveal the island while Game Mode remains active. An ordered-out island cannot
activate the app or intercept mouse/keyboard input. Restoration does not make
the window key or activate the application. Restoration immediately recomputes
click-through at the current pointer position, so a stationary pointer can click
the restored island. It prepares keyboard handling (still gated by key-window
status) without consuming the next real pointer entry. The startup mouse-poll
fallback is stopped while hidden.
Occlusion suppresses the glow, while existing provider/history refreshes remain
unchanged. Display switching never overrides suppression.

`Tests/GameModeTests.swift` exercises preference persistence, combined lock/game
transitions, hidden-window input gating, startup during Game Mode, and real
Darwin notification delivery in a unique test namespace. Tests never write or
post Apple's Game Mode notification. Live acceptance additionally needs an
actual game entering/leaving Game Mode and a check that foreground focus is
preserved, including a launch while Game Mode is already active.

`Tests/WindowInteractionTests.swift` compiles the real window controller against
window/input/store spies. It exercises hide/restore beneath a stationary pointer,
outside-pointer click-through, compact/peek modes, combined suppressors, unlock,
focus preservation, the next real pointer entry, and keyboard-monitor lifecycle.
The regression fails against the controller before the restoration fix. It
does not display windows, capture or inject system input, activate applications,
or establish live AppKit/SwiftUI event behavior.

## Keep history preparation outside interaction updates

`OverviewView` observes cost data and constructs the current-year snapshot.
`OverviewContent` receives that snapshot as a value and owns provider/day
selection. Resizing the island does not invalidate the history summary. Page changes are received
as events to clear day details without rebuilding the grid when no day is selected.

Do not put the calendar join back in a computed property read by each summary,
accessibility label, and grid. That repeats date arithmetic and provider aggregation
several times within a single view update. Cost publications still refresh the
snapshot, including new dates and provider records.

Contribution cells have a fixed width. Their provider segments use that width
directly, avoiding a geometry reader and an extra layout pass for each active day.
Keep per-day hover, selection, help text, and accessibility intact when changing
how the grid is drawn.

## Reproduce transition stalls

Run `scripts/benchmark-rendering.sh` from a logged-in graphical macOS session.
It builds a separate demo app, mounts the real `ExpandedView`, and repeatedly
changes pages and both chart styles for twelve seconds. The first two seconds
are warm-up. It does not start application polling, scan session logs, or start
the updater; preferences belong to a separate benchmark bundle.

The output reports main-run-loop timer intervals: p95, p99, maximum, and the
number of gaps over 25 ms. These are a signal for main-thread stalls, **not
measured display FPS or GPU presentation times**. The timer requests 120 Hz;
macOS scheduling and other running apps affect the results. Compare repeated
runs on the same machine with the same workload, and do not run other builds
or tests during the measurement.

For before/after comparison of history changes, set
`RENDER_BENCHMARK_OVERVIEW_SOURCE` to a saved copy of `OverviewView.swift`.
Both versions then use the same harness and compiler options. Use
`RENDER_BENCHMARK_PREVIEW=1 scripts/benchmark-rendering.sh` to leave the demo
window open for manual checks; stop the process afterward.

The benchmark covers content transitions, not the outer island glow, material
halo, mouse tracking, or Settings. Profile those separately before attributing
cost to them. Remaining candidates include the continuously shaded glow,
blurred chart transitions, and keeping offscreen carousel pages mounted.
Any page-unmounting optimization must preserve provider selection, outgoing
transition content, rapid navigation, and the first-use carousel cue.

## Content-sized carousel

`ContentSizedPageLayout` measures the selected page at the available width with
an unspecified height. Its horizontal position is animatable, but its selected
page is discrete: a half-finished swipe must not select a different page's height.
Each page remains mounted, retaining provider selection and transition content.
Graph pages supply their own vertical padding; calendar details participate in
normal layout rather than requesting a fixed height increment from the model.

The expanded island wraps this intrinsic content. Its shape and background follow
the resulting bounds. A geometry preference mirrors those bounds into
`IslandModel.size` for mouse hit testing; that value does not constrain expanded
layout. There are no graph/calendar height presets or page/height subscriptions.

The native `CompositedPageStrip` prototype remains available, but the carousel
no longer uses its separately sized hosting view. SwiftUI owns both page sizing
and placement. The cost count-up timeline retains its 120/60/30 frame policy;
carousel motion is system-paced. Recheck transition performance when changing
this layout, and do not restore a second independent source of height.

## Page height regression checks

Run `scripts/benchmark-rendering.sh Tests/PageHeightTests.swift` in a graphical
macOS session. It measures real page heights, then opens the actual island and
navigates 0, 5, 20, or 80 ms into its opening animation, including rapid
cost → usage → cost → overview reversals. It verifies each destination settles
at its measured content height. A separate layout fixture checks that an
intermediate horizontal position still uses the selected page's intrinsic height.

Testing only settled page changes misses the opening-animation interruption.
Live checks should also select a calendar day and confirm that the detail strip
expands the panel without clipping, then navigate back to a graph.
