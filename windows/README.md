# CodexIsland for Windows

The WPF app runs in Windows 11, with x64 and ARM64 installers and an updater
described in [UPDATES.md](UPDATES.md). Normal launches use local accounts, including portable and development copies.
Sample data requires an explicit preview selection.
**Settings > Providers > Connect accounts** switches to local accounts and remembers that choice.
The provider connection paths are documented in [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md).
Windows uses a pill with one or two provider icons surrounded by quota rings,
with percentages and reset times beside them.
It reveals on hover at the top center, and clicking expands into the existing usage panel.
The collapsed pill floats 12 logical pixels below the top edge. The expanded panel touches the top edge and preserves the Mac's original silhouette.
Provider icons stay visible and move into the header as the pill expands. A shared spring coordinates
the shape and icon positions and preserves velocity when reversed. Dismissing the expanded panel follows the Mac hover-out sequence: content fades over 100 ms,
and width and height start contracting 20 ms later using the 0.30 response, 0.88 damping spring.
It stays attached to the top edge. The last compact silhouette fades away on Windows, where
there is no physical notch, before preparing the next hover pill.
Reduced motion and keyboard shortcuts settle immediately; the animation stops rendering once it settles.
The expanded layout, chart geometry, colors, and typography derive from the Mac source.
Island typography, effects, and motion refinements are recorded in
[VISUAL-REFINEMENT.md](VISUAL-REFINEMENT.md). Share-card typography and measured layout corrections are recorded in
[CARD-PARITY.md](CARD-PARITY.md). Complete parity of the expanded experience remains unverified.
See [PARITY.md](PARITY.md) for the implemented scope, evidence, and remaining differences.
Performance is part of the same requirement. See [PERFORMANCE.md](PERFORMANCE.md) for measured workloads,
rendering changes, and the remaining device-validation requirements.

## Run from the Mac

With Windows 11 running in Parallels and the Mac home folder shared:

```sh
bash windows/run-parallels.sh
```

Pass a different VM name as the first argument if needed. The script copies source to the guest's local
app-data folder, publishes an ARM64 executable with its runtime, creates a desktop shortcut, and launches it.
Later, double-click **CodexIsland Prototype** on the Windows desktop to reopen it.

First-time prerequisite, in Windows PowerShell:

```powershell
$root = Join-Path $env:LOCALAPPDATA 'CodexIslandPrototype'
New-Item -ItemType Directory -Force $root | Out-Null
Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile "$root\dotnet-install.ps1"
powershell -ExecutionPolicy Bypass -File "$root\dotnet-install.ps1" -Channel 10.0 -Architecture arm64 -InstallDir "$root\dotnet" -NoPath
```

## First launch

A first live launch briefly reveals the actual pill, with a small guide directly underneath it.
The guide explains top-center hover and click-to-open, and offers **Connect accounts** and **Got it**.
It waits eight seconds before closing; hovering or keyboard focus pauses dismissal. Clicking the pill
opens the normal usage panel and finishes the guide. **Keep pill visible** remains respected.

Automatic guidance does not take keyboard focus. Full-screen content, a locked session, and suspension
defer it until the display is available. Reduced motion shows the guide without its entrance animation.
Completion is saved only after dismissal or a meaningful action, so an interrupted first launch can
retry. Completed guidance is not shown on later launches. Existing preview users see it once when
upgrading to the first version with this introduction.

The tray menu includes **Settings** and **Show introduction**. Explicit replay supports keyboard focus,
Tab, Enter, and Escape. Direct `--settings` / `--providers` launches and sample-data previews do not
automatically show the introduction. English and Simplified Chinese follow the current app language.

`tests/run-window-motion.ps1 -Variant introduction` checks the running native window in an isolated live
profile, including pointer hit testing, focus, timing, provider settings, persistence, suppression, and
reduced motion. `tests/check-introduction-startup.ps1 -PackagePath <package> -ReceiptPath <output>` tests
first launch, automatic completion, and a normal restart from the actual packaged executable.

## Try it

- Pause for 200 ms at the display's top center, above the pill's 112 or 192 logical-pixel width.
- Move into the pill; it stays open. Leaving the collapsed pill for 400 ms dismisses it.
- Each provider ring shows its primary quota, following the Used or Remaining setting. Missing readings use a dashed neutral ring; a real zero keeps a solid track. Hover an icon for the exact reading.
- Click to expand. The panel dismisses on pointer exit, Escape, or an outside click. **Keep pill visible** in General settings makes the collapsed pill persistent instead.
- Click the center page dots, scroll, or use Ctrl+1/2/3 to select Usage, Cost, or Overview.
- Click the footer style chip or Ctrl+click to cycle chart styles. The gear opens Settings.
- Select calendar days for detail, click provider legends to filter, and use Share usage to open the usage-card studio.
- Ctrl+Alt+I opens or dismisses the expanded panel if the shortcut is available.
- The system-tray menu opens usage or settings, replays the introduction, hides the island, reduces motion, or quits.
- Settings persist locally. Launch at Login enables or disables startup registration; an existing entry
  also follows an explicit change between live and demo data.
- Settings pickers and card export actions share a compact dark menu with a right-side selection mark.
  Arrow keys, Enter, Escape, and outside-click dismissal remain available.
- Currency rates load from the same public service as the Mac. Normal launches use live accounts,
  including portable and development copies. Older settings recover to live mode on their next load;
  display preferences and usage history are retained. Sample data requires an explicit preview selection.
  Use live accounts in the tray menu (or `--live`) reads Windows CLI credentials for Codex, Claude, Grok, and Antigravity.
  Real Codex and Antigravity requests are verified; Claude/Grok account acceptance and other provider
  behaviors remain incomplete. Local session history supplies costs, model rows, the calendar, and cards;
  [HISTORY.md](HISTORY.md) describes the supported readers, persistence, and remaining recovery work.
  **Preview sample usage** in the tray returns to sample values; `--demo` forces that mode for one launch.
- In live mode, **General > History backup** imports a Mac or Windows history ledger and saves portable
  backups. Imports preserve existing records and save the previous ledger before merging. Recovered
  daily totals keep their original dates and remain unpriced when model evidence is missing.
- `--data-dir <absolute-folder>` opens a separate data profile. Its settings, history, and caches survive
  a restart independently of the default profile. The CLI account stores remain owned by their CLIs.
- Available Codex reset credits appear beside the account name. Hover or focus the badge to see
  expiration dates; Escape closes the details. The panel does not consume credits.
- Live sparklines retain actual quota observations across restarts. Saved readings appear while
  refreshing only after the current account is identified, and expire with their quota window.
  **Collecting history** remains visible until there are two samples. Saved readings do not trigger
  fresh alerts. Storage and account limitations are in [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md).

The cursor monitor is event-driven. Reveal and dismissal timers only run while waiting for a transition.
Wheel and horizontal-scroll packets are grouped into one adjacent page change per gesture. The Overview
calendar retains its drawing during page motion and rebuilds when its data or interactive state changes.
Animations respect Windows' client-area animation preference and the tray's Reduce motion toggle.
The top-center trigger follows the monitor under the cursor while hidden. Display changes hide and reposition it.
Settings can pin the island to a display. Windows energy saver activates the Low Power behavior automatically;
its event registration has been verified, but a real battery-saver transition has not. The island hides over
foreground full-screen content and stops its glow until the display is available again. Alert thresholds,
four-second peeks, focus behavior, and outstanding platform cases are described in [BEHAVIOR.md](BEHAVIOR.md).

The guest's `%LOCALAPPDATA%\CodexIslandPrototype\state.json` records the latest state, display, focus handle,
and WPF rendering tier for local verification. It also records provider status categories in live mode,
without tokens, account identities, or quota readings. Launching with `--trace-frames`
adds bounded, in-memory drawing and composition timing; it writes `frame-trace.json` only when that
diagnostic session closes. Normal runs do not install the composition observer.
`--preview-alerts` is a separate fixture-only verification mode. Normal demo launches suppress automatic
alert pulses, matching the Mac demo.

## Verification

The build and local interaction/rendering checks run in Windows, not through a Mac cross-compiler.
The current checks cover hover timing, focus, click-through, page navigation, chart-style cycling,
calendar disclosure, keyboard and accessibility actions, six card export formats/metrics, clipboard copying, and settings persistence. All chart variants are captured
and compared with settled renders of the real SwiftUI source. These checks do not constitute visual
approval. Typography, effects, settings/backend, and motion gaps remain listed in [PARITY.md](PARITY.md).

Build output is staged before replacing the running copy so a compilation failure preserves the last
working application. Source and test artifacts stay under `windows/`; the Mac release, credentials,
usage history, Sparkle configuration, and production app remain unchanged.
