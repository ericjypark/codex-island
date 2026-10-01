# Windows performance verification

Performance is part of the full parity requirement. Passing these checks does not establish identical
frame pacing, power use, or behavior on a physical Windows PC.

## Workload and measurement boundaries

The Windows measurements use the running ARM64 application in Windows 11 in Parallels at 200% display
scaling. The normal app has no frame observer. Each idle scenario settles for 1.5 seconds and measures
six seconds of process CPU time. Percentages are relative to one CPU core, not the whole computer.
The stress sequence interrupts page transitions 54 times across six blocks and records process memory,
handles, graphics resources, and UI-thread response to a window message. That response time is not
input-to-display latency.

The Mac reference builds the real `IslandRootView` and its effects with optimization in a separate demo
application. A temporary source copy supplies initial hover, pill, and content visibility states. It uses
the normal AppKit application event loop, the same provider pair, a 220 × 38 pt notch, and an 800 pt
expanded panel. This measures settled rendering, not the physical hover gesture or production accounts.
The first manual-run-loop harness was rejected because it introduced a busy loop while animating.

Both workloads contain fixture account data. They do not measure Windows authentication,
log scanning, recovery, or the live-provider workload. Native Mac and virtualized Windows CPU percentages
provide separate reference measurements; they are not a controlled platform-speed ranking.
The user's Windows top-center reveal means its hidden rest state differs intentionally from the Mac's
visible compact state. Those two states must not be compared as equivalent workloads.

## Findings and changes

- The initial normal-app sequence measured 34.3% of one core on settled Overview, 13.3% on Usage,
  and 12.7% on Cost. Hidden rest measured 0%; Low Power rest measured 0.26%.
- A targeted trace showed the island's drawing callback stopped after transitions, while the rotating
  glow continued at its intended 30 Hz. The high settled cost therefore was not repeated reconstruction
  of the whole island on the UI thread. Composition remained the next area to isolate.
- Whole-panel bitmap caching reduced the initial Overview sample to 12.7%, but its default resolution
  blurred text at 200% scaling. Display-resolution caching restored sharpness but still changed text-edge
  pixels. Whole-panel caching was rejected. It is not part of the current app.
- Zero-radius blur effects are removed when transitions settle. Blur remains active during transitions.
- The calendar grid has its own display-resolution cache, while all text continues through native drawing.
  The cache retains the original cell geometry, provider stripes, selection, hover, and page translation.
  Grid-edge antialiasing differs from direct rendering; this remains a recorded rasterization difference,
  not evidence that visual parity has been accepted.
- Changing Low Power during a running count-up previously left the clock at its old cadence. The rendered
  regression check reproduced both directions: about 17 ms after enabling Low Power and about 32 ms after
  disabling it. The animation now reschedules from the displayed value with its remaining duration.
  It does not jump backward or restart from zero. Reduced motion immediately shows the target value,
  and completed counters remove their animation clocks.

## Mac settled reference

These are six-second samples from the optimized reference on this Mac, at 2× on a display reporting
120 Hz. The sample is not a sustained 120 FPS measurement.

| State | CPU, percent of one core |
| --- | ---: |
| Compact rest | 10.36 |
| Peek, hovered | 12.02 |
| Usage, settled | 36.82 |
| Cost, settled | 26.14 |
| Overview, settled | 29.27 |
| Always-visible rest | 11.53 |
| Low Power rest | 0.01 |

## Current Windows sequence

The calendar-cache build is `af4e7a3d-4b2e-4df6-aafd-9d63df22edd1`. The before sequence used
`67e038df-8a41-4282-8ae9-0db1bb2387fc`. These are individual six-second samples, so small differences
should not be treated as a demonstrated improvement or regression.

| State | Before, one-core CPU % | Current, one-core CPU % |
| --- | ---: | ---: |
| Hidden | 0.00 | 0.00 |
| Peek, hovered | 10.40 | 11.43 |
| Usage, settled | 13.26 | 14.81 |
| Cost, settled | 12.73 | 11.70 |
| Overview, settled | 34.32 | 15.58 |
| Always-visible rest | 10.91 | 10.90 |
| Low Power rest | 0.26 | 0.26 |
| Hidden after stress | 0.00 | 0.00 |

The 54-transition stress sequence averaged 59.1% of one core, compared with 64.7% before. The slowest
block's 95th-percentile window-message response was 4.8 ms, compared with 5.8 ms before. However,
one response reached 72.2 ms, compared with an 18.2 ms maximum before. That outlier needs targeted
attribution and repetition; this sequence does not establish identical worst-case responsiveness.

Private memory at the ends of the stress blocks ranged from 273 to 284 MB, compared with 254 to 265 MB
before. After hiding and settling it returned to 109 MB, compared with 92 MB before. The cache has a
memory cost. This short sequence does not establish long-running memory stability or prove a leak.

The same installed build's count-up trace recorded 3.2 ms p95 for island drawing and 0.071 ms p95 for
individual retained dollar-glow updates. Active-count-up composition-callback intervals were 17.0 ms
median, 20.1 ms p95, and 48.2 ms maximum. The remaining long interval needs investigation; these
callbacks do not establish physical presentation FPS.

Six separate rendering checks passed. Low Power changes during a running animation produced median
value-update intervals of 31.6 ms when enabled and 17.2 ms when disabled, with no backward movement.
The counter finished at 644 and 659 ms in those two scenarios. A side-by-side uncached control matched
within one color-channel value. The current cache preserved text within one channel value and matched
the sampled calendar-fill interiors exactly. Calendar-edge antialiasing changed, with a maximum
58/255 channel difference at some edges and a 0.237/255 mean difference across the measured opaque area.
The raster check reports those differences explicitly and does not label the entire panel pixel-identical.

## Required performance coverage

### Third-page swipe regression

The user's report of lag when swiping, especially on Overview, led to a separate page-navigation trace.
The calendar's grid cache reduced settled composition cost, but the drawing code still rebuilt its
calendar, text, and interactive targets on every page-animation frame. Overview now retains a frozen
vector drawing and its calendar commands while page movement changes only their position. Data, local
date, selection, hover, culture, and display scale invalidate that drawing. The retained text is not a
whole-panel bitmap cache.

Three repeated keyboard transitions into Overview in the running VM produced these results. Each
composition interval is included from navigation until the next navigation, capped at 650 ms. The
separate drawing measurements include all Overview drawing callbacks in the trace.

| Measurement | Before | After |
| --- | ---: | ---: |
| Overview drawing, p95 | 9.295 ms | 0.060 ms |
| Composition callback interval, median during entry | 30.519 ms | 17.780 ms |
| Composition callback interval, p95 during entry | 51.620 ms | 30.602 ms |
| Longest composition interval during entry | 59.313 ms | 49.362 ms |

Before is build `8ebd7e71-c066-4f00-89f7-6cef3f71ff71`; after is
`62275d02-866e-4431-afd9-325544387444`. The provider pair, chart styles, and 200% scaling were the same;
the user changed the compact notch spacing between those runs. These are separate VM observations,
not a controlled hardware FPS result. Occasional long intervals remain. The full after trace includes
a 121.7 ms startup interval, which is outside the measured page-entry windows.

An actual WPF regression reproduced repeated calendar rebuilding before the change. Its five checks
now pass: leaving and returning does not rebuild an unchanged Overview; all 265 interactive targets
return; the settled pixels are unchanged; selecting and clearing a day each invalidate the cache once.
Six counter/raster checks also pass after integration. Their results retain the previously documented
calendar-edge antialiasing difference.

The input check independently found that native wheel messages reached the overlay but did not reach
its WPF wheel event. The native window hook now handles vertical and horizontal wheel packets. Small
packets accumulate to one deliberate step; a committed burst cannot skip additional pages, and a
direction reversal remains responsive. Seven logic cases and three running-app scenarios cover a
single notch, eight small vertical packets, and eight small horizontal packets. All three native
scenarios failed before the hook and passed after it. Their before CPU samples did not navigate, so
they are not valid navigation-speed baselines. Physical touchpad gesture phases remain unverified.

The 15 hover/focus/click-through checks passed on the integrated build. The five-second hidden sample
recorded 15.625 ms CPU (0.312% of one core). This is a separate idle observation, not a frame-pacing
measurement. Recalculation after a live model-price update also runs on a worker thread; large actual
history archives still need a measured responsiveness test.

### Coverage still required

The subsequent alert/window pass verified stopped sweep timers during full-screen suppression, including
a scheduled alert while a full-screen window remained in the foreground. Its five-second settled
full-screen sample recorded 0 ms CPU. The updated hover regression sequence recorded 46.875 ms CPU
over five seconds while hidden (0.938% of one core). These are separate samples, not a new ambient
performance comparison. Exact behavior checks and build identifiers are in [BEHAVIOR.md](BEHAVIOR.md).

- Hidden, visible, hovered, expanded, Low Power, minimized/occluded, suspended, and resumed states.
- Open/close, interrupted page navigation, chart switching, count-up, calendar detail, and alert pulses.
- Effective Low Power changes during active motion, including a real Windows energy-saver transition.
- Presentation frame pacing on a physical Windows display at its supported refresh rates and scales.
- UI response, startup and first-use latency, export latency, long-running memory, and graphics resources.
- Live-provider fetching and history scanning with large actual Windows archives.
- No optimization may silently remove an effect, lower its intended cadence, or obscure missing data.

## Reproduce

- `tests/check-performance.ps1`: normal running app, idle and interrupted-navigation measurements.
  `-OutputName` preserves separate before/after files in ignored artifacts.
- `tests/check-render-cost.ps1`: opt-in drawing attribution. Its frame observer makes it unsuitable for
  idle CPU measurements.
- `tests/check-motion.ps1`: count-up drawing time and composition-callback intervals. These are timing
  diagnostics, not proof of frames presented to the display.
- `tests/run-render.ps1`: a separate WPF test window using the actual app assembly. It checks mid-animation
  Low Power changes, monotonic values, completion, reduced motion, settled clocks, and side-by-side raster
  output. `-ProbeCache` runs the rejected whole-panel-cache experiments and is expected to report differences.
- `reference/performance.sh`: optimized Mac reference, raw JSON and scenario captures.
- `tests/check-window-context.ps1`: native full-screen suppression and a five-second idle CPU sample.
- `tests/check-alerts.ps1`: background fixture pulses, Low Power glow, and full-screen interaction.
- `tests/check-swipe.ps1 -RequirePass`: native wheel/scroll bursts and repeated navigation with a bounded
  frame trace. `-OutputName` preserves separate reports. The normal app mode and page are restored.
- `tests/run-swipe-render.ps1`: unchanged calendar reuse, interactive targets, round-trip raster output,
  and selection invalidation through the actual WPF surface.

Run process measurements sequentially. Do not compile or run another rendering workload during an idle
sample. Raw results include build identifiers where applicable and live under `windows/artifacts/`.

## Live pointer and retained-page investigation (2026-09-12)

The user's report concerned hover and clicking throughout the live preview. A native regression
reproduced three complete calendar rebuilds while crossing three footer controls, and seven rebuilds
while crossing six dates. A keyboard focus ring also remained after mouse interaction.

Mouse input now clears the previous virtual focus target. Tab navigation still restores focus.
Calendar hover draws a separate outline, while the calendar and page drawing remain retained.
Usage and Cost retain their vector drawings during page movement. Glowing values move with a retained
parent transform; their text still updates during the count-up. Feed revision, configuration, currency,
locale, scale, minute boundaries, and expired quota windows invalidate the relevant content.
These changes do not introduce a whole-panel text bitmap or remove effects.

Two baseline samples used 60.27% and 60.08% of one CPU core during Overview control hovering.
The final build used 34.20% and 37.87% in two samples of the same sequence. A preliminary hover-only
change measured 25.32%, illustrating the variation between these short VM samples. The frame observer
was enabled in these runs; these are not normal idle-power measurements. Usage body drawing at the
95th percentile fell from 1.02-1.82 ms in the baselines to 0.028 ms in the first final run. The calendar
body fell from 3.27-3.50 ms to 0.057 ms. Cost still redraws its changing counter.

This is a partial performance improvement. The final native mouse-click sequence measured 60.19 ms
median and 67.72 ms maximum from injected input to the selected page-dot pixels in the Windows guest.
It includes desktop pixel readback and excludes the host display and physical input path. A repeated
trace still contained a 225 ms UI-response outlier. It is not appropriate to claim that lag is resolved.

Attribution placed the first drawing submission roughly 9-14 ms after injection, with the visible
change arriving later. A plain Windows control and simple opaque, layered, and glass WPF controls
measured roughly 16-17 ms. Those references rule out treating the delay as an unavoidable cost of all
Windows controls or transparency alone. Removing graphics effects, using DWM glass, and forcing
software rendering in isolated copies did not establish an overall solution. They were not adopted.

The final implementation passed 13 hover, retention, focus, pixel, and expiry checks; 89 native
live-rendering checks; and six counter/raster checks. The existing calendar-edge antialiasing
difference remains; the counter/raster test measured text differences of at most one channel value
and unchanged sampled cell interiors. These checks do not establish Mac visual or physical performance
parity. The same live history total and original preferences were verified after installation.

Reproduction uses `tests/measure-live-responsiveness.ps1 -Snapshot <verified-history-snapshot>` and
`tests/check-live-pointer.ps1`. Both target the separate profile explicitly. The measurement harness
restores the original executable and preferences. `-PointerOnly` records native clicks; `-RawClicks`
omits accessibility inspection. `run-presentation-probe.ps1`, `measure-pointer-reference.ps1`, and
`probe-graphics-effects.ps1` are diagnostic reference experiments. The effects script stages a separate
copy and restores the original preview. Bounded diagnostic traces now include input, navigation, drawing,
and composition timestamps on a shared monotonic clock; normal launches do not enable those traces.

## Full-window expansion and dismissal (2026-09-12)

The friend's report was specifically opening and closing the pill in an installation displaying sample
data. The comparison therefore runs the packaged application with its full transparent window, native
shadows, blur, rotating border, and sample data. It invokes the same `MainWindow.SetState` path as the
normal click handler, in a separate profile, without moving the pointer or replacing an installed app.
It measures application drawing and composition callbacks, not physical input-to-display latency.

The reproduced defects were an unused dollar counter invalidating Usage and Overview during expansion,
and shell geometry advancing twice when WPF supplied the same rendering time. The counter now runs only
for the dollar view; each composition time advances the shell once. The rotating border also coalesces
path rebuilding until drawing and reuses its pens and brushes. Its 30 Hz cadence, color calculation,
line thickness, blur, and shadows are unchanged. The shape cache checks the current render size directly
so an undelivered size-change event cannot leave the old outline in use.

Two alternating before/after runs used Windows 11 ARM in Parallels, hardware rendering tier 2, at 200%
scaling. Each run opened and closed Usage and Overview four times each. The table pools 16 expansions
and 16 dismissals per build. Before is the packaged 0.2.5 build
`aa62ea76-f1cf-4606-a02b-b729ba1a41ba`; after is the private 1.0.0 ARM64 candidate
`83f13d43-e493-452a-a30b-97b936c98bb9`.

| Measurement | Before | After |
| --- | ---: | ---: |
| Expansion, mean process CPU time | 358.4 ms | 303.7 ms |
| Expansion, mean managed allocation | 25.15 MB | 12.89 MB |
| Expansion, total island drawing calls | 876 | 404 |
| Expansion, composition interval p95 | 31.33 ms | 28.91 ms |
| Expansion, longest composition interval | 60.96 ms | 50.18 ms |
| Dismissal, mean process CPU time | 89.8 ms | 101.6 ms |
| Dismissal, composition interval p95 | 16.87 ms | 17.11 ms |
| Dismissal, longest composition interval | 34.19 ms | 44.35 ms |

Expansion used approximately 15% less CPU time, 49% less managed allocation, and 54% fewer island drawing
calls. Dismissal did not demonstrate a performance improvement in these samples. Long composition
intervals remain, and this does not establish that the friend's physical-PC stutter is resolved.
Neither the process CPU time nor the composition callback count is a physical FPS measurement.

`tests/run-window-motion.ps1` runs this workload from current source or a supplied `-PackagePath`.
`-Variant regression` checks the actual main-window counter and duplicate-frame paths, then compares the
border against the previous renderer at seven sizes/shapes and four rotation positions. Those 28 stroke
rasters are pixel-identical. This comparison covers the border's drawing primitives; unchanged effects,
text, whole-window visuals, and physical presentation remain separate observations.
Use distinct `-OutputName` values for successive runs. `-Architecture x64` selects the x64 helper when
testing an x64 package. Diagnostic `no-counter`, `no-sweep`, and `no-shadows` variants change only the
isolated test process; they are not app preferences or shipping effect removals. Raw alternating runs
and their summary are under ignored `artifacts/pill-performance-compare/`.
