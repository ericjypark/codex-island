# Rendering performance

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
