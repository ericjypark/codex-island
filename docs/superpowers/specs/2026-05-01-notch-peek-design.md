# Notch peek: hover for headline, click to enter

**Date:** 2026-05-01
**Status:** Approved, ready for plan

## Problem

Today, hovering anywhere on the compact island silhouette springs open the full
expanded panel. This is fast, but two issues:

- It opens too eagerly. Bumping the cursor past the notch on the way to a menu
  bar item is enough to trigger a full panel expansion.
- It doesn't surface the one number a glance-user actually wants — "how much of
  my 5-hour Claude / Codex window have I burned?" — without the panel reflowing
  the entire desktop above it.

Goal: hover gives a calm, low-commitment headline; the full panel only opens on
explicit intent (click).

## Interaction model

The `IslandModel.State` enum gains a third case: `peek`, sandwiched between
`compact` and `expanded`.

| State | How you get here | What you see |
|---|---|---|
| `compact` | Default | Black silhouette = notch + two 38pt logo tabs. No percentages. |
| `peek` | Hover the silhouette | Silhouette springs wider on each side. Each side shows: logo (in its old position) + a percentage pill outboard of it: `"32% · 2h"`. No expanded panel content. |
| `expanded` | **Click** the silhouette | Full Usage/Cost panel as today. |

### Transitions

- `compact → peek`: hover-in. Spring widens the silhouette; pills fade in with
  a small outward slide as the shape grows around them.
- `peek → compact`: hover-out without clicking. Pills fade first (~80ms), then
  silhouette springs back.
- `peek → expanded`: click. Single continuous spring from peek-width to
  expanded-width — pills travel outward with the growing shape, then cross-fade
  out ~250ms after the expanded content has settled. No reset beat.
- `expanded → compact`: hover-out (today's behavior, unchanged).
- `compact → expanded` (cold click without prior hover): supported. Same
  `openMorph` spring; pills aren't shown because peek was skipped.

The headline behavioral change: **hover no longer opens the full panel**. Hover
only peeks. Click is required to enter.

## Pill visuals

- **Content:** `"32% · 2h"` — 5h used percentage + time-until-reset, separated
  by a middle dot (`·`).
- **Reset format:** `Nh` when ≥ 1h remaining, `Nm` when under 1h.
  - Examples: `"3h"`, `"47m"`, `"1h"`. Never mixed (`"1h 47m"` is too noisy for
    a glance pill).
- **Background:** continuous with the black silhouette — pill has no separate
  chip; it's text painted on the dark shape, like the logos.
- **Color:**
  - Number ("32%"): tinted with `IslandColor.claude` / `IslandColor.codex` to
    match the adjacent logo, at the same intensity as the logos themselves.
  - Reset suffix ("· 2h"): white at ~70% opacity — quieter, secondary read.
- **Typography:** existing `Typography` numeric style for consistency with the
  expanded panel's percentages.

### Empty / error states

| Condition | Pill |
|---|---|
| Provider visible, fresh `usedPercent` available | `"32% · 2h"` |
| Provider visible, fresh `usedPercent` available, no `resetAt` | `"32%"` (no suffix) |
| Provider visible, loading first time, no prior good value | tiny spinner dot in pill slot |
| Provider visible, errored, no prior value | `"—%"` |
| Provider visible, prior good value present, refresh in flight | keep showing last good value (don't blank) |
| Provider toggled off in `ProviderVisibilityStore` | no pill on that side; silhouette only grows on the opposite side |

The "keep prior value during refresh" rule mirrors the existing
`UsageStore.isErrorOnly()` guard — a transient 429 should never blank the
glance number.

## Architecture

### `Sources/Model/IslandModel.swift`

Add `case peek` to `State`. Add a `peekWidth` calculation in `recomputeSize()`:

```swift
let pillSlotWidth: CGFloat = 78   // fits "100% · Nh" worst case + ~10pt gap to logo
let leftSlot  = ProviderVisibilityStore.shared.claudeVisible ? pillSlotWidth : 0
let rightSlot = ProviderVisibilityStore.shared.codexVisible  ? pillSlotWidth : 0
size = CGSize(
    width: notch.width + tabWidth*2 + leftSlot + rightSlot,
    height: notch.height
)
```

Implementation should validate the 78pt against rendered text width with the
chosen `Typography` style and adjust if needed (within ±15pt). The slot width
is fixed so percentage updates (32%→33%) don't jitter the silhouette width.

The fixed slot width avoids per-frame width jitter as percentages change
(e.g. 32% → 33% during refresh). Pill text right-aligns on the leading side and
left-aligns on the trailing side, hugging the logos.

Hidden providers contribute zero to the slot width on their side (asymmetric
peek shape — only one side grows).

### `Sources/Views/IslandRootView.swift`

Replace the current `onHover` body with a state machine:

```swift
.onHover { h in
    hovering = h
    if h {
        haptic(.levelChange)
        withAnimation(.openMorph) { model.setState(.peek) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard model.state == .peek else { return }
            withAnimation(.easeOut(duration: 0.18)) { pillsVisible = true }
        }
    } else {
        withAnimation(.easeOut(duration: 0.08)) { pillsVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard !hovering else { return }
            withAnimation(.closeMorph) { model.setState(.compact) }
        }
    }
}
.onTapGesture {
    if NSEvent.modifierFlags.contains(.command) { /* existing cycle behavior */; return }
    guard model.state == .peek || model.state == .compact else { return }
    withAnimation(.openMorph) { model.setState(.expanded) }
    // pills cross-fade out 250ms after click
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        withAnimation(.easeIn(duration: 0.18)) { pillsVisible = false }
    }
}
```

Add `@State private var pillsVisible = false`. On entering `.peek`, fade pills
in (delayed 60ms with `.easeOut(0.18)` so the eye sees the shape commit
first). On entering `.expanded` from `.peek`, pills stay mounted until the
+250ms cross-fade.

### New view: `Sources/Views/NotchPeekPill.swift`

```swift
struct NotchPeekPill: View {
    let usage: WindowUsage
    let loading: Bool          // UsageStore.shared.loading
    let tint: Color            // IslandColor.claude or .codex
    let alignment: HorizontalAlignment

    var body: some View { ... }   // renders the rules in the table above
}
```

Owns the loading/error/value rendering decisions. Stateless — pure function of
its inputs.

### Wiring in `IslandRootView`

Add two new overlays alongside the existing logo overlays:

```swift
.overlay(alignment: .topLeading) {
    if model.state != .compact && visibility.claudeVisible {
        NotchPeekPill(
            usage: usageStore.claude.fiveHour,
            loading: usageStore.loading,
            tint: IslandColor.claude,
            alignment: .leading
        )
        .opacity(pillsVisible ? 1 : 0)
        .offset(x: pillsVisible ? 0 : 6)   // small slide-in from outboard
        .padding(.leading, /* outboard of logo */)
    }
}
.overlay(alignment: .topTrailing) { /* mirror for codex */ }
```

No new data fetching. Reads from existing `UsageStore.shared`.

## Animation timing (the "smoothness" knob)

| Transition | Spring/curve | Notes |
|---|---|---|
| compact → peek (shape) | `.openMorph` (existing) | |
| compact → peek (pills) | `.easeOut(0.18)`, +60ms delay | Shape commits first, pills follow |
| peek → compact (pills) | `.easeOut(0.08)` | Pills fade out |
| peek → compact (shape) | `.closeMorph` (existing), +80ms delay | After pills fade |
| peek → expanded (shape) | `.openMorph` (existing) | Single continuous spring from peek-width → expanded-width |
| peek → expanded (expanded content) | `.strongEaseOut`, +220ms delay (existing) | Unchanged |
| peek → expanded (pills) | `.easeIn(0.18)`, +250ms delay | Cross-fade out after expanded content has settled |

The single `openMorph` spring carrying the shape from peek-width all the way
to expanded-width is the core smoothness move — no double-bounce, no
intermediate snap.

## Accessibility

- `accessibilityHint` on the silhouette in `compact`/`peek` updates to:
  "Hover to peek usage. Click to expand. Command-click to cycle visualization."
- Each pill gets an `accessibilityLabel` like
  `"Claude: 32 percent of 5-hour window used, resets in 2 hours"`.
- VoiceOver users without trackpad hover get a focus order: silhouette →
  Claude pill → Codex pill → settings (when expanded).

## Out of scope

- Weekly % display, plan-tier badge, click-to-cycle on the pill — not added
  (we picked just `5h% · reset` for the glance read).
- Changes to the existing expanded panel layout, Cost view, or settings.
- Telemetry / analytics on hover-vs-click.
- Animating between asymmetric peek widths when a provider is toggled
  on/off mid-hover (rare; settle on next hover-in is fine).

## Files touched

- `Sources/Model/IslandModel.swift` — add `peek` state, `peekWidth` math.
- `Sources/Views/IslandRootView.swift` — replace `onHover` body, add tap →
  expand logic, mount `NotchPeekPill` overlays, add `pillsVisible` state.
- `Sources/Views/NotchPeekPill.swift` — new file, ~50 lines.

No changes to:
- `UsageStore`, `UsageFetcher`, `AppUsage` — existing data flows untouched.
- `ExpandedView`, `UsageView`, `CostView` — expanded state behavior unchanged.
- `IslandWindowController`, `BorderlessFloatingWindow` — window sizing comes
  from `IslandModel.size` which already drives the host view; widening for
  peek is automatic.
