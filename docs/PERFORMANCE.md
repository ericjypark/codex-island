# Rendering performance

## Fullscreen visibility

`FullscreenStore` hides the island in the current native fullscreen Space or
with optional Accessibility detection, when a foreground application's visible
window fills the island's selected display. `MacIsland.hideInFullscreen` defaults to true and has an independent
General setting. This covers native fullscreen video and Split View. Optional borderless detection
supports apps that emit Accessibility window notifications. Fullscreen on another
display does not hide the island. A shared native Space (when displays do not
have separate Spaces) applies to all displays.

Apple documents `NSApplication.currentSystemPresentationOptions` as observable,
but it reported no fullscreen flag while Firefox occupied a native fullscreen
Space on the tested macOS 26.6 system. `FullscreenSpaceReader` instead optionally
resolves `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces` at runtime. These
are undocumented, read-only WindowServer interfaces. It inspects only the target
display's `Current Space` type (0 for desktop, 4 for fullscreen), not other
Spaces. Missing symbols, display mappings, or unfamiliar payloads fail open.

Native fullscreen detection reads at startup and on Space, application activation/termination,
wake, display-change, target-selection and unlock events. Screen-parameter events
are owned by the window controller: it updates the recorded placement before
refreshing fullscreen and scheduling bounded settling checks. The store does not
independently sample a possibly disconnected display during that notification.
Disabling fullscreen
hiding stops all fullscreen queries and detaches the Accessibility observer.
System/display sleep and session lock also suspend detection. Native suppression
is retained while suspended until a fresh resume snapshot, so the fullscreen
store cannot reveal the window before the separate controller lock handler runs.
A separate pending gate also holds display while suspended, including when the
cached native result is false and borderless detection is off. It clears only
after the resume sample, so controller-first unlock and display changes while
locked cannot expose stale native state. Disabling fullscreen hiding clears
both the cached result and pending gate.

Borderless detection is a separate, default-off opt-in (`MacIsland.detectBorderlessFullscreen`).
Turning its toggle on requests Accessibility permission when access is missing.
The request uses [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
with the prompt option; macOS
shows the request asynchronously and the user grants access in System Settings.
Startup, restored preferences, Recheck, and OS events never prompt. Settings
provides Recheck and Open Settings actions; Open Settings targets the Accessibility
permission pane and reports a dispatch failure with manual navigation instructions.
Recheck clears that stale dispatch error once trusted access is observed, without
opening Settings again or prompting.
Native fullscreen needs no Accessibility permission.

`FullscreenAccessibilityMonitor` attaches one AXObserver to the foreground app.
It observes focused/main-window changes and window creation, plus resize, move,
destruction and minimize/restore notifications on up to 32 app windows. It
reconciles registrations when events arrive, replaces the observer on app
or display changes, and releases its run-loop source/observer when disabled or suspended.
If observer creation fails transiently, the next event or Recheck retries the
same context; a recovered session is reused. No idle retry is scheduled.
AX creation, messaging and registration run on a dedicated serial worker with a
sleeping run loop, away from the UI thread. Calls have a 50 ms timeout and each
reconciliation slice has a 200 ms budget (one in-flight call can finish beyond that
deadline). An incomplete slice queues a cancellable continuation, retaining its
window snapshot and operation cursor. The finite plan handles up to 32 windows;
each registration/removal advances even when unsupported. Completion is published
only after the plan finishes, so budget exhaustion cannot clear suppression or
require another external event. Completed work returns to the sleeping run loop. Window-creation
notifications remain attached while the foreground app has no windows.
Callback contexts remain owned until their observers detach; request and
observation revisions reject stale results and callbacks after context changes.
Rechecks keep the current borderless suppression and reuse registrations while
the foreground process and selected display are unchanged. A context change
clears that result before observing the new context; delayed replies are checked
against the current process and display before reading geometry.
The first borderless result, a changed context, and wake/unlock rechecks gate
window display until the current asynchronous snapshot resolves, for at most
750 ms of initial AX waiting per context. This one-shot deadline is not reset by
same-context refreshes or reconciliation slices. On expiry, a not-yet-confirmed
window is shown while reconciliation continues; a late current result can still
hide it. Established same-context fullscreen suppression is never cleared by
the deadline. Context changes, suspension, opt-out, permission loss, completion
and teardown cancel the deadline; no retries or queries are scheduled by it.
This pending
state is separate from detected fullscreen. It prevents startup activation from
changing the foreground app being inspected and avoids an interactive flash on
resume. After native sampling resumes, missing permission or unsupported
notifications clear the remaining borderless wait; opt-out always clears the gate.
Foreground eligibility is checked before publishing a pending gate. The island,
Finder, and a missing foreground app skip borderless observation without briefly
hiding the island on activation; native fullscreen suppression remains independent.
[Notification support](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification)
is app-dependent. Missing permission or unsupported geometry
notifications leave borderless suppression off and show a status in Settings.
Some apps accept registrations but never emit events; same-app changes can then
be missed until another workspace event or manual Recheck. There is no recurring
polling fallback.

Notification bursts are debounced into two delayed snapshots (80 ms after the
latest event, then 350 ms later), allowing transition geometry to settle. A new
event cancels and replaces pending delayed checks, including a trailing event
after the first snapshot. Reads do not schedule more reads.
Workspace events also get an immediate snapshot. Permission is rechecked before
observer/geometry work; detected revocation releases the observer and clears stale
borderless suppression. With no events there is no immediate revocation detection:
returning from System Settings, a workspace event, or Recheck refreshes the state.

Once notifications are available, `FullscreenWindowReader` reads on-screen window
metadata using `CGWindowListCopyWindowInfo`. Foreground, visible, nontransparent
window edges must match the selected `CGDisplayBounds` within two points. Finder,
the island, background apps, inactive Spaces, spanning windows and work-area
maximized windows do not qualify. A manually sized edge-to-edge window does.
No pixels, window titles, browser content or Accessibility text values are read.
Neither reader changes Spaces. Accessibility is used only for window membership
and notifications; Screen Recording permission is not needed.

All enabled suppressors must clear before restoration. The combined visibility
subscription seeds state before first display and preserves the input/focus
safeguards below. Game Mode may briefly outlast a fullscreen transition.

`Tests/FullscreenTests.swift` covers Space and window geometry fixtures, visibility
composition, notification refresh, opt-in and permission states, unsupported apps,
burst coalescing, absence of idle polling, cancellation, sleep/lock, and teardown.
It also covers uninterrupted suppression during unrelated application exits and
rejects delayed replies after foreground-process or target-display changes.
Delayed snapshots also exercise startup and sleep/lock resume gates, including
unsupported results that leave the island visible.
`Tests/FullscreenAccessibilityTests.swift` runs the actual worker and monitor
against injected AX sessions, checking window replacement, registration bounds,
windowless apps, transient creation recovery, unsupported notifications, partial reconciliation, slow queries,
stale callbacks, off-main execution and teardown. Both suites observe at least
three idle seconds without additional queries. This establishes query behavior,
not a battery or CPU-energy measurement.
The monitor and trust status are injected: tests neither request Accessibility
permission nor inspect live apps. Injected request/open handlers verify user-toggle
requests, quiet startup/Recheck, the Settings URL and failed-dispatch recovery,
including Recheck after a manual grant. Delayed replies verify the 750 ms gate
across same-context refreshes, idle stability, late results, retained suppression
and cancellation across app changes and lock.
A late controller lock-handler fixture verifies native suppression has no transient
clear before the controller processes the same lock notification. A controller-first
unlock fixture changes the selected display while locked and verifies that only a
fresh native sample can release the resume gate. Window
interaction tests cover restoration and focus guards. These checks do not
establish live AX notification delivery.
Live acceptance requires separate approval: native browser fullscreen/Space
switches, supported and unsupported borderless apps, app/window replacement,
permission grant/revocation, selected displays, sleep/lock, and preserved focus.

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
state. The main-queue lock callback installs the lock flag synchronously before
queued Game Mode/fullscreen updates can clear other reasons. Ending a game cannot
reveal a locked session and unlocking cannot
reveal the island while Game Mode remains active. An ordered-out island cannot
activate the app or intercept mouse/keyboard input. Restoration does not make
the window key or activate the application. Restoration immediately recomputes
click-through at the current pointer position, so a stationary pointer can click
the restored island. It prepares keyboard handling (still gated by key-window
status) without consuming the next real pointer entry. The startup mouse-poll
fallback is stopped while hidden.
Restoration resets hidden pulse/expansion state to the configured compact or peek
state before computing the mouse-hit area, so discarded bounds stay click-through.
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
hidden pulse/expansion restoration, focus preservation, the next real pointer
entry, and keyboard-monitor lifecycle.
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

`IslandModel.showScreen` commits page selection without an animation transaction.
`PagedContent` applies `.pageSwipe` when that committed selection changes. Keep
the animation at the view boundary: wrapping the shared selection mutation in
`withAnimation` could retain the previous page body when provider data published
in the same turn, even though the footer already showed the new selection.

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
The same root-view test checks Credits addition/removal and 12 simultaneous
provider-publication/navigation sequences, covering all pages with and without
Credits. These checks need a graphical session and are separate from the headless
Swift regression suite.

Testing only settled page changes misses the opening-animation interruption.
Live checks should also select a calendar day and confirm that the detail strip
expands the panel without clipping, then navigate back to a graph.
