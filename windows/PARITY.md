# Windows parity work

The Windows collapsed view intentionally differs from the Mac: it is a pill with provider
quota rings, percentages, and reset times. It reveals on hover by default and expands on click.
The compact layout is 192 logical pixels wide for two providers or 112 for one, with the
same 52-pixel height, provider rings and reading sizes.
The collapsed pill floats 12 logical pixels below the top edge. The expanded view touches the top edge and retains the Mac's original shape and layout.
The pill and expanded header use the same provider icons. Their positions, shell geometry and top offset
share a spring; expanded content stays clipped to the shell during the transition. Expanded dismissal starts on pointer exit, fades content over 100 ms, and starts the Mac
close spring (response 0.30, damping 0.88) 20 ms later. Width and height contract toward
the Mac compact silhouette while the top remains fixed. Windows fades the final compact
silhouette rather than retaining a physical-notch outline. Reversal preserves velocity,
reduced motion settles immediately, and the render callback detaches at rest.

Status of the expanded experience: **not accepted as identical**. The goal still includes motions, effects, typography, settings,
performance, and the complete user experience. The items below record implementation and evidence; they do not
redefine that goal or turn passing functional checks into visual approval.

## Reference

`reference/render.sh` hosts the real SwiftUI views in a separate demo application. Production Swift
files, accounts, preferences, release metadata, and Sparkle keys are not edited. Two temporary source
copies in ignored artifacts let the capture select a calendar date and disable the reference app's
updater startup. Without the latter, Sparkle opens a configuration alert in the capture process.

Views settle in an NSHostingView before capture. The fixture contains all four providers' demo values,
daily tokens, billable tokens, dollar totals, chart series, and model rows. Date-dependent captures and
the fixture must be regenerated together.

The baseline uses Codex and Antigravity with a 220 × 38 pt notch at 2× output. Usage and Cost measure
800 × 226 pt. Overview measures 800 × 277 pt, or 800 × 335 pt with selected-day details.
The card reference includes Feed, Square, and Story with both API value and token metrics.
Capture preferences represent the state after chart discovery, so the cycle hints are hidden on both
platforms. Calendar detail uses the fixture date. Reset countdowns use each capture's local clock.

## Implemented

- Source colors, logo assets, expanded content dimensions, five quota chart styles,
  four cost styles, page controls, style cycling, and daily contribution history.
- All four provider selections, swapping, single-provider layouts, nullable quota handling, used/remaining
  preference, token-counting preference, and source day details. Overview intentionally counts all tokens.
- Open/close springs, delayed pill/content fades, page movement, blur/scale/opacity chart changes,
  dollar count-up, the rotating gradient glow, low-power gating, discovery movement, edge feedback,
  and the day-detail blur/scale disclosure. Dollar glows use retained composition layers.
- Three settings tabs with saved preferences, recovery copies for malformed settings, provider selection,
  display pinning with disconnected-screen fallback, pill visibility, language choice, launch-at-login registration,
  threshold controls, and reduced motion. Some platform/backend actions remain incomplete below.
- Shared dark picker/export menus remove the system-white checkmark gutter and retain native menu-item
  keyboard and accessibility behavior. The Providers page follows the Mac's selection-first layout,
  with only the selected accounts beneath it. Windows CLI sign-in remains available for disconnected
  selected accounts; connected account actions use compact controls or the account context menu.
  Demo/live switching is in the tray menu, using the existing persisted-mode restart handler.
  The previous eighteen mode checks exercised the older settings entry point, not the new tray entry.
- Windows energy-saver notifications feed the same effective Low Power predicate as the user toggle.
  Registration and the current system state were observed in the VM; a real battery-saver transition
  has not been verified. Counter animations request 30 fps under Low Power, reschedule when the mode
  changes during an animation, and settle immediately with reduced motion.
- Currency conversion using the same public rate service as the Mac, daily caching, offline retention,
  whole-unit currencies, and USD fallback until a valid rate exists.
- Opt-in Codex/Claude/Grok/Antigravity usage requests from read-only Windows CLI credentials, bounded re-reading after
  rejected tokens, selected-provider refresh, cooldowns, cancellation, account separation, and visible
  error states. Live mode excludes all fixture history and costs. Real Codex and Antigravity accounts return live usage; Claude/Grok account acceptance and complete
  provider behavior remain unfinished; see [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md).
- Persistent quota observations and identity-checked launch restoration, recorded-data sparklines,
  per-window expiry, and alert suppression for saved readings. Live charts show their actual sample
  history; the Mac's decorative curve with fewer than six observations is intentionally not reproduced.
- Local Codex, Claude, Grok, Antigravity CLI, and OpenCode history readers, a durable SQLite ledger,
  independent provider scans, model pricing, local-calendar aggregation, and recorded-data cost/model/
  calendar/card views. Missing logs preserve retained usage; unknown prices remain explicit. Mac/Windows
  ledger import, transactional backup/restore, original-date daily recovery, and separate data profiles
  are implemented. Real Windows archive discovery and direct Claude statistics recovery remain unfinished;
  see [HISTORY.md](HISTORY.md).
- Usage-card studio with all five periods, both metrics, all three image formats, provider inclusion,
  signature limits, fit/actual-size preview, PNG export, image/caption copying, and Windows Share integration.
- Keyboard navigation and automation peers for the island, plus semantic settings/card controls.
  Eight accessibility/keyboard checks passed. Full screen-reader behavior still needs verification.
- The calendar grid caches its shapes at display resolution to reduce settled rendering cost. Text remains
  native. Six rendering checks cover mid-animation power changes and raster controls; calendar-edge
  antialiasing remains a recorded difference. Current performance results are in [PERFORMANCE.md](PERFORMANCE.md).
- Overview retains its drawing during page motion instead of rebuilding the calendar on every frame.
  Native wheel/horizontal-scroll handling groups small packets into one adjacent page step. The five
  calendar-render and three native-input regression checks pass; physical touchpad behavior remains
  unverified.
- Branded application/tray icons, display/session changes, focus restoration, transparent hit testing,
  Escape, outside click, and pointer-exit dismissal. Always-visible mode retains the peek strip.
- Source alert thresholds, startup suppression, reset-cycle deduplication, per-provider warning/critical
  colors, and the four-second pulse lifecycle. Normal demo mode suppresses pulses; a separate fixture
  launch exercises them. Window event hooks hide the island over foreground full-screen content and
  stop its glow. Details and remaining platform cases are recorded in [BEHAVIOR.md](BEHAVIOR.md).

## Evidence so far

- Build and UI checks run in Windows 11 ARM in Parallels at 200% scaling.
- The interaction harness has passed 15 hover/focus/click-through checks, including direct re-entry after
  automatic dismissal. That regression failed before the dismissal-suppression fix. After history/swipe integration,
  the five-second hidden sample recorded 15.625 ms of CPU time (0.312% of one core); earlier samples recorded
  31.25 ms, 46.875 ms, and 0 ms.
  Neither sample establishes physical-PC performance or animation frame pacing.
- Eight settings checks verified persistence, provider swapping, token mode, refresh interval, and
  always-visible behavior in a running build.
- Twelve card checks verified six export dimensions, signature limiting, clipboard results, sizing control,
  and disabled export when every provider is deselected. The accessibility checkbox binding was corrected
  after this check initially failed.
- 350 logic checks cover provider credential/request/cooldown behavior, all five history readers, durable
  retention and corrections, malformed data and storage failures, model pricing, scroll-packet grouping,
  alert decisions and primary limits, monitor geometry, local-midnight/DST
  countdowns, settings recovery, calendar boundaries, card totals and tier rounding, valid/invalid currency
  responses, offline caching, and currency labeling.
- Seventy-five render checks and fifteen installed-app checks cover live connection states,
  recorded cost/model/calendar/card values, retention after log deletion/restart, and absence of fixture
  values in live views. The installed-app test uses isolated missing credentials;
  separate live runs verified Codex and Antigravity account requests. Capture caveats are in [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md).
- A frozen 1,000-point Mac weekly quota series survives the Windows cache without substituted values.
  Native used/remaining plots were compared with the actual Mac chart renderer. Controlled restart
  cases cover saved values before network completion, offline retention, identity separation, and expiry.
- Nineteen running-app alert checks cover pulse timing, focus, hover/expanded ownership, Low Power, and
  an alert arriving during full screen. Seventeen window-context checks cover real borderless full-screen
  windows, ordinary maximize, minimize/hide, restoration, and startup. A five-second full-screen-suppressed
  sample recorded 0 ms CPU. Builds and platform limitations are recorded in [BEHAVIOR.md](BEHAVIOR.md).
- The native Windows share dialog was observed with the generated PNG thumbnail and file loaded.
  It was dismissed without selecting a destination. No transmission was tested or performed.
  The shell share surface was not exposed by the UI Automation window-name query; the PNG
  capture, rather than those query booleans, is the evidence of the loaded payload.
- A frozen real Mac ledger and price table passed 1,774 Windows comparison and import checks. Daily
  totals, model breakdowns, cumulative costs, and all five card periods match output from the actual
  Mac sources. Duplicate imports, backup/restore, recovery provenance, and restart without source files
  are covered. Native renders and an isolated interactive profile use the copied history. This verifies
  history parity for that snapshot, not complete visual or account parity.
- The comparison generator verifies dimensions for 21 panel, settings, studio, and card pairs,
  and checks provider-heading visibility on panels. Pixel differences are diagnostic, not a quality score.
- An opt-in runtime trace measured the previous software text-glow drawing at 43.1 ms p95 during
  count-up. Retained WPF effect layers reduced island drawing to 3.2 ms p95 in the final VM sequence
  (build `67e038df-8a41-4282-8ae9-0db1bb2387fc`). After excluding duplicate rendering callbacks and
  measuring only count-up intervals, composition-callback intervals were 17.0 ms median,
  30.4 ms p95, and 39.3 ms maximum. Callback timing is not a physical display presentation
  measurement, and frame pacing is still not identical. Raw traces carry build IDs.

These checks apply to the builds on which they ran. The app records its build identifier in `state.json`
so future verification can associate results with a specific executable.
Performance measurements, rejected optimizations, acceptance coverage, and platform limits are recorded
in [PERFORMANCE.md](PERFORMANCE.md).

## Remaining work

- The island uses embedded Inter text faces and calibrated Cascadia Mono/Consolas numerics.
  [VISUAL-REFINEMENT.md](VISUAL-REFINEMENT.md) records typography, effects, motion, and their checks.
  Settings retain native Windows typography. Share cards use
  embedded Inter faces with rounded numeric outlines, measured baselines, and corrected section
  spacing. [CARD-PARITY.md](CARD-PARITY.md) records the corrections and verification. Glyph shapes
  still differ from the Mac's SF fonts. Apple's font terms exclude non-Apple interface use and software embedding:
  [Apple fonts](https://developer.apple.com/fonts/). SF font files have not been copied into the port.
- Some text shapes/metrics, SF Symbol replacements, blur/shadow kernels, and rasterization
  still differ. Motion timing constants are ported, but frame pacing and intermediate frames need comparison.
- Alert pixels and intermediate frames, exclusive full-screen games, virtual desktops, actual lock/suspend
  and DWM cloaking transitions, a real system energy-saver transition, and comprehensive accessibility/
  localization checks remain incomplete. Fixture pulses and ordinary borderless full screen are covered
  by the running-app tests in [BEHAVIOR.md](BEHAVIOR.md).
- Complete provider behavior remains unfinished: real Claude/Grok account validation, Claude renewal,
  launch seeding for CLI-backed/project-scoped identities, real Windows archive validation, and recovery
  from Claude statistics files. Codex has a CLI-backed account reader and live reset-credit panel;
  native account reads and 75 render checks pass. Separate real keyring/encrypted account
  provisioning remains unverified. The first launch uses a labeled
  demo and the tray menu can switch to live data. Local recorded history is implemented; missing evidence remains unavailable. Production update
  delivery also has no Windows release feed.
- A physical Windows PC, other display scales, x64 packaging, multi-monitor hot-plug, signing, installation,
  and distribution still need validation or implementation.

## Verification entry points

Build with `bash windows/run-parallels.sh`. PowerShell scripts in `tests/` use the shared repository
folder and the running app. `run-logic.ps1` builds isolated logic checks with temporary fixture files.
`check-interaction.ps1`, `check-parity.ps1`, `check-preferences.ps1`, and `check-card.ps1` exercise the app.
`check-native-share.ps1` opens and dismisses Windows Share without choosing a target.

Some harness setup is sequential: preference checks require Settings to be open; native share checks
require the card studio. `check-settings.ps1` now verifies island accessibility and keyboard actions. `check-motion.ps1`
restarts only the preview with opt-in frame diagnostics, exercises count-up, saves its trace, and reopens
the preview normally.
`check-performance.ps1` records idle CPU, interrupted navigation, response timing, and memory in a normal
run. `run-render.ps1` exercises actual WPF counter scheduling and compares cached/uncached rendering.
`check-alerts.ps1` exercises alert fixtures and restores normal demo mode. `check-window-context.ps1`
checks real full-screen, maximize, minimize, hide, restoration, and suppressed CPU behavior.
`run-live-render.ps1` checks controlled provider responses through the actual WPF surface;
`check-live-ui.ps1` checks the installed live-mode UI with isolated missing credentials.
`check-swipe.ps1 -RequirePass` checks native wheel/scroll input and page-entry timing;
`run-swipe-render.ps1` verifies retained Overview drawing, targets, and selection changes.
`check-dropdowns.ps1` checks shared menus, keyboard/mouse behavior, and the persisted account-mode flow.
Run `python3 windows/tests/compare-renders.py` after current Mac and Windows captures exist.
The generated HTML and PNGs are local artifacts under `windows/artifacts/`.

## Providers settings correction (2026-09-12)

A direct comparison with `ProviderSelectionView.swift` found that the Windows page had added a demo
banner and a four-account list before provider selection. Those elements were not present in the Mac
layout. The current page begins with the two slots, follows their order for account rows, and shows
compact connection controls. Sign-in actions remain available for selected accounts that require them.
Account actions for healthy legacy providers are available through the heading's context menu.
The demo/live selector is now in the tray menu.

Settings now uses the bundled Island Text faces and grayscale text, with opaque label colors matched
to the dark surfaces. Provider dropdowns, swap, connection refresh, account options, and quota
disclosure have explicit vector icons. Token counting uses the compact two-line control, and the Cost
row combines its scan caption, attribution, currency picker, and refresh action. Cost refresh also scans
local history. Existing quota selections, sign-in handlers, and account credentials are preserved.

Fresh Mac source renders at 480 by 720 and 440 by 560 were compared with Windows desktop captures.
The Providers layout build passed 95 live-render checks and 12 settings checks, including first-presentation
text pixels, the bundled font, selected-account order, one-provider behavior, quota selection, login
transitions, and narrow control bounds. The corresponding ignored artifacts are in
`artifacts/provider-settings-confirmed/`. Reproduce with `reference/render.sh --settings-only`,
`tests/run-live-render.ps1 -SettingsOnly`, and the full `tests/run-live-render.ps1`.

The caption follow-up removes the inset that clipped the 12-point Close and Zoom circles. Its source
passed 14 settings checks, including both circles fitting without layout clipping. Native desktop
captures were refreshed at 200% scaling; the broader 95-check run above predates this caption fix.

Tooltips now have a shared dark surface and explicit text styling, fixing the light text on the default
light Windows popup. Settings fixtures load the actual application resources. All 16 settings checks
pass, including native Close and Zoom tooltip captures with visible text. The installed application's
style source and binary were verified separately; the full 95-check run predates this follow-up.

This fixes the substantial layout mismatch. It does not establish pixel identity: Inter and Cascadia
have different outlines from SF Pro and SF Mono, and some native menu/control details still differ.
The Mac reference captures SwiftUI content without its native window controls; the Windows captures
include their window frame. The fixtures also have different scan timestamps. These differences are
called out in the comparison, rather than treated as passing visual parity.
