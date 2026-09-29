# Alert and window behavior

The Windows implementation now includes the Mac alert decisions and pulse lifecycle, plus native
full-screen suppression. This is implementation and test evidence, not acceptance as visually or
functionally identical across every platform condition. Live Codex and Antigravity connections are
verified; real Claude/Grok account validation remains unavailable. See [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md).

## Alerts

`AlertEngine.cs` follows `Sources/Model/AlertEngine.swift`:

- Severity follows the visible provider's primary limit, using consumed percentage even when the UI
  displays remaining percentage. Codex falls back to its weekly limit when its five-hour reading is
  missing; a real zero remains a valid five-hour reading. Claude keeps its five-hour primary.
- The first completed update establishes crossing memory without a notification. High usage can tint
  the island immediately. Missing values cannot become a real zero or a threshold crossing.
- Restored quota values retain severity but cannot create or prune live crossing memory. Each restored
  provider's first live response establishes its baseline silently, even if another provider already
  refreshed. An offline restored provider does not suppress fresh alerts from another provider.
- Warning and critical crossings are remembered separately per provider and reset boundary. Falling
  below a threshold and recrossing it in the same cycle does not repeat the notification. A changed
  reset boundary permits a new crossing. Missing reset boundaries preserve existing crossing memory.
- Simultaneous crossings produce one event containing the affected providers and highest severity.
  Disabling alerts or using invalid thresholds clears both severity and crossing memory.
- Normal demo updates retain severity but suppress pulses, as the Mac demo does. The explicit
  `--preview-alerts` launch flag exposes fixture-injection buttons in General settings for verification.
  It does not connect accounts or change the demo provenance labels.

An unattended pulse opens a peek, holds it for four seconds, fades the pills over 80 ms, and begins
closing after a 100 ms wait. Hover, an expanded panel, and Always show usage retain ownership of their
respective state. Automatic peeks do not activate the window. Expanded panels consume the crossing
without opening a new peek. Warning and critical use the source amber/red values, including separate
provider pill colors. Active alerts retain the event glow in Low Power mode.

Hidden-to-peek uses the source opening spring (response 0.42, damping 0.82). Returning from expanded
uses the closing spring (0.30, 0.88). Pill fades now use the standard ease-out curve. Halo color changes
use 450 ms ease-in-out and opacity changes use 250 ms ease-in-out; cursor events no longer restart an
in-flight halo animation toward an unchanged target.

The native pointer tracker also synchronizes reset-credit hover after changing the overlay's
click-through state. A first move directly into the badge after expansion previously failed to open
details until a second move. The installed-app test reproduced that failure and passed after the
correction, including movement into the panel, Escape, and reopening.

## Full screen and visibility

The Mac source pauses its sweep when its native window is occluded. The Windows topmost overlay also
needs to hide when another foreground application's client area covers its target monitor. It uses
[window event hooks](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook)
for foreground, geometry, minimize, hide, and desktop/cloaking changes. Notifications are coalesced on
the dispatcher. There is no periodic full-screen polling timer.

The test compares screen-space client bounds against the target monitor. Normal maximized windows
with a title bar are excluded, as are the desktop/shell, invisible or minimized windows, and this
application's own windows. DWM cloaking and session lock/suspend state also suppress the overlay.
While suppressed, it is hidden, click-through, nonactivating, and its glow timer stops. Automatic alerts
update their severity without revealing the island. On restoration, Always show usage returns to peek;
ordinary hover mode returns to its hidden rest state.

The Windows event and geometry behavior is based on Microsoft's
[event constants](https://learn.microsoft.com/en-us/windows/win32/winauto/event-constants),
[client coordinates](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclientrect),
[screen conversion](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-clienttoscreen),
and [DWM attributes](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute).

## Verification

`run-logic.ps1` includes the original alert and monitor-geometry cases plus six saved/live alert
regressions, within the current 350-check suite.
The alert checks cover warmup, deduplication, escalation, reset changes, hidden providers, absent and
invalid readings, rounding, demo suppression, re-enabling, and primary-limit selection. Geometry checks
include negative monitor coordinates, another display, a spanning client, and a maximized title bar.

`check-alerts.ps1` drives the running app through its Settings controls. It verifies pulse timing, focus,
hover and expanded ownership, per-provider severity, disabling, Low Power, and full-screen suppression.
All 19 checks passed on build `bd18c691-39e5-40aa-b103-1317526a7064`.
The full-screen alert case schedules a fixture update three seconds later, then gives the full-screen
window foreground focus. This tests a background update without activating the Settings button mid-test.
`check-window-context.ps1` creates a real WinForms window, changes between ordinary, maximized, and
borderless full-screen states, and checks both app state and pixels copied from the Windows desktop.
Both scripts preserve preferences and return the preview to a normal launch without fixture controls.

The full-screen sequence passed 17 checks on build `ec2654be-baea-4352-b43a-a709a8f5f046` in Windows 11
ARM in Parallels at 200% scaling. The screenshot
at the island's position contained the full-screen application's background without overlay pixels.
The suppressed process consumed 0 ms of CPU during the five-second settled sample. This measurement
does not establish behavior on a physical PC, battery use, or presentation frame pacing.

The alert test also exposed a hover regression: timed dismissal set the same suppression flag as a
manual dismissal while the pointer was still inside. A direct return from outside to the trigger could
then stay hidden. `check-interaction.ps1` gained checks for re-entry and successful expansion before
testing outside-click dismissal. Both new checks failed before the fix. Suppression now applies only
when dismissal occurs with the pointer inside the island or its trigger. The harness now returns failure
when a behavioral assertion fails, rather than only writing the failed assertion to JSON.
Preference diagnostics are written after the glow predicate updates, so recorded Low Power and sweep
states describe the same update. Redundant diagnostic writes during that path were removed.

Raw results and captures are in ignored `windows/artifacts/`, with the app build identifier recorded
in alert/context results. `check-alerts.ps1 -InputOnly` isolates hover after relaunch for investigation.

## Not yet verified

- Actual lock/unlock, suspend/resume, secure-desktop changes, and DWM cloaking transitions.
- Exclusive Direct3D games, other virtual desktops, display hot-plug, and mixed-DPI physical monitors.
- A real Windows energy-saver transition and physical presentation timing during alert motion.
- Pixel-level equivalence of warning symbols, typography, halo kernels, and intermediate animation frames.
- Alert delivery from live provider updates and durable usage history, which still require their services.
