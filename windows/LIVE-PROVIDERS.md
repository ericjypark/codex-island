# Windows provider connections

The Windows app connects to Codex, Claude, Grok, and Antigravity. A fresh installer
launch reads local CLI accounts. Standalone development copies start with labeled
sample data; choose **Use live accounts** in the tray menu to switch. The choice
persists across ordinary launches.

In **Settings > Providers**, select the left and right providers. Their account
controls appear below the selectors. Install the provider CLI when needed, then
use its sign-in button. Each official CLI owns its browser sign-in flow.
Antigravity first asks for **Google OAuth** in its terminal. Completing sign-in
refreshes the connection automatically. The app follows one active CLI account
per provider; **Switch account** changes that CLI session. **Preview sample usage**
in the tray returns to sample data without modifying CLI accounts.

The command-line override remains available; close an existing instance before using it:

```powershell
& "$env:LOCALAPPDATA\CodexIslandPrototype\app\CodexIslandPrototype.exe" --live
```

Live mode uses the island's existing provider selection, refresh presets, alerts, and Low Power behavior.
The Providers tab offers install, sign-in, account-switching, and manual usage refresh actions. Opening a CLI is a user
action; starting the island does not start a login, make a CLI inference request, or install a provider.
App-requested restart preserves the mode. The account action also returns to Providers after restarting.
An already enabled launch-at-login entry follows an explicit data-mode change; the action never enables
startup on its own. A real Windows sign-in/startup run remains unverified.

Installation uses the providers' fixed official HTTPS PowerShell installers. It runs only after the
install button is clicked, checks for a completed CLI installation, and shows retryable failures in
Accounts. Executable detection includes fresh user/machine PATH values and native/npm/WinGet paths,
so an app restart is not required after installation. Sign-in delegates to `codex login`,
`claude auth login`, `grok login`, or the interactive `agy` launcher. No login output is captured,
and account setup never directly writes credentials. Antigravity can stay open after sign-in; the
app observes its credential metadata and releases its busy state when a valid session appears.
Duplicate setup actions remain disabled across settings-window closure and reopening.

Installer sources: [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) and
[Claude Code setup](https://code.claude.com/docs/en/setup),
[Grok CLI](https://docs.x.ai/build/overview), and
[Antigravity CLI](https://antigravity.google/docs/cli/install).

The official Grok 1.0.30 ARM64 executable overflowed its main-thread stack during login in the
Windows ARM VM. Account setup uses the same official release
[for x64](https://x.ai/cli/grok-1.0.30-windows-x86_64.exe) under Windows emulation, preserving the
original CLI executable. The workaround is restricted to that ARM64 version, validates the downloaded
PE architecture and reported version, and invalidates its registration when either executable changes.
It does not replace a newer native release or write account data.

## Data and credential boundaries

- Codex reads `tokens.access_token` from `$CODEX_HOME/auth.json`, or `.codex/auth.json` under the Windows
  user profile. File-based sessions use the existing HTTP reader. An explicit non-file storage mode
  delegates account and quota reads to the installed CLI's `app-server` protocol, so the CLI owns
  access to its OS/encrypted backend. The bridge does not fall back to an old credential file. A separate
  process cannot recover another process's ephemeral session; unavailable accounts remain disconnected.
  The lightweight file-mode configuration reader does not implement the complete TOML configuration schema.
- Claude first considers `CLAUDE_CODE_OAUTH_TOKEN`, then reads `claudeAiOauth.accessToken` from
  `$CLAUDE_CONFIG_DIR/.credentials.json`, or `.claude/.credentials.json` under the Windows user profile.
  Subscription type is available from file-based credentials. Plan metadata for an environment-only
  token is not inferred. The app does not read Claude Desktop's private credential storage.
- Grok reads `$GROK_HOME/auth.json`, defaulting to `.grok/auth.json`. It prefers valid current-issuer
  sessions and retains user identity for the documented CLI billing headers. Expired credentials are
  rejected before requesting quota.
- Antigravity reads the CLI-owned Windows Credential Manager item `gemini:antigravity`. The native
  UTF-8 payload and the CLI base64 wrapper are supported. The actual Windows account connection has
  validated this storage mapping. The app never writes this item.
- Reads are bounded and read-only. The app does not call an OAuth refresh endpoint, rewrite a CLI
  credential file, copy credentials from the Mac, or log bearer tokens or response bodies. Credential
  objects have redacted string output and no serializable token properties. Account identifiers are
  hashed for account separation and the local quota cache. An absent or empty identity falls back to a hash of the access token,
  which clears retained quota on an unidentifiable token change rather than merging accounts. The CLI
  bridge receives no access token; without a backend account ID it cannot retain prior-account readings.
- Request destinations are fixed. The production HTTP client rejects redirects and applies a 20-second
  timeout and 1 MiB response bound for Codex/Claude. Grok/Antigravity requests use a 12-second
  main-request timeout and 2 MiB bound; the optional Grok settings read is limited to two seconds. Controlled tests inject an HTTP handler; the shipped app does not
  expose an endpoint override that could redirect a real credential.

The current CLI contracts are documented by
[OpenAI's auth storage implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs),
[OpenAI's storage-mode defaults](https://github.com/openai/codex/blob/main/codex-rs/config/src/types.rs), and
[Claude Code authentication](https://code.claude.com/docs/en/authentication).

## Request and error behavior

Codex requests `/backend-api/wham/usage` on `chatgpt.com`. It routes primary/secondary windows by their
reported duration, using the slot only when duration is missing. Missing percentages stay unavailable;
a reported zero stays zero. A successful response replaces the reported window set, so an omitted
window cannot inherit an obsolete value.

The CLI bridge initializes a bounded stdio session, sends `account/read` with `refreshToken: false`,
then reads `account/rateLimits/read` with reset-credit details requested and reserve capacity disabled.
It prefers the `codex` entry in `rateLimitsByLimitId`, falling back to the legacy snapshot. API-key,
Bedrock, and signed-out accounts do not trigger a subscription quota request. Native executables and
PowerShell/command launchers are supported. The reader has a 30-second deadline, bounded protocol
messages, and cleanup of its own process. It discards CLI stderr and never forwards server requests
for token refresh or user actions. The protocol follows the
[official Codex app-server account documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints).

Successful file-based Codex quota reads also request the Mac source's fixed
`/backend-api/wham/rate-limit-reset-credits` GET endpoint within the same request deadline. Optional
credit errors retain valid quota; a credit-endpoint 429 still imposes its cooldown. Missing summaries,
count-only details, known-empty detail arrays, and a known zero stay distinct. Prior credit details
survive an unavailable lookup only for the same identified account.

Available credits with known future expiration dates enable the header badge. It displays the service's
available count and up to three expiration rows, ordered by date. The hover panel follows the Mac's
210-point width, downward anchor, 180 ms reveal, 90 ms exit, 80 ms crossing grace, and 120 ms badge fade.
It uses localized absolute dates, supports keyboard focus and Escape, and respects Reduce motion and
Low Power. The panel reports availability and expiration; it has no redemption action.

Claude requests `/api/oauth/usage` on `api.anthropic.com` with the Mac source's bearer, JSON accept/content
headers, `anthropic-beta: oauth-2025-04-20`, and `claude-code/2.1.121` User-Agent. Utilization is always a
percentage: `0.5` means half of one percent. ISO and Unix reset times are supported. A 401 or Claude 403
re-reads credentials, excluding previously rejected tokens, with at most three token attempts. A 429,
including `rate_limit_error` inside HTTP 200, stops credential probing immediately. A Codex 403 reports
denied usage access and does not trigger credential probing or logout.

Grok requests subscription credit usage from `cli-chat-proxy.grok.com/v1/billing?format=credits`,
with its CLI identity headers. Unified/monthly plans can require the additional billing response.
Optional billing/settings failure preserves usable quota; an optional 429 still imposes a cooldown.
Extra spending does not count as subscription quota. A Free plan without a quota reading displays
**No active subscription**, while a real zero remains a valid reading.

Antigravity resolves its project with `loadCodeAssist`, then requests `retrieveUserQuotaSummary`
from `daily-cloudcode-pa.googleapis.com`. Both requests use the CLI's scoped backend. Grouped quotas
preserve missing values. Under **Usage display**, each account can choose its model group, first and
second metric, and the primary metric used by peek and alerts. Choices persist per account; a missing
chosen metric stays unavailable instead of substituting another group's quota.

A metadata-only five-second watch detects credential changes and refreshes only the affected provider.
It does not perform five-second API polling. Expired Grok/Antigravity sessions can invoke one bounded
CLI `models` command and reread the resulting credentials. The CLI owns token renewal. Forbidden and
rate-limited responses do not invoke renewal. Claude's automatic renewal ping remains unimplemented.

Selected supported providers are fetched. While the Accounts section is open, all four providers are
also observed so accounts outside the island selection can connect. Leaving Providers settings
returns automatic polling to the selected providers. Concurrent refreshes join the same request batch.
Changing selection cancels that batch and prevents late results from publishing. Automatic polling
uses the existing 5/15/30-minute presets. Rate limits impose at least 15 minutes plus 10 seconds of
cooldown, honor a longer Retry-After, and cannot be bypassed by manual refresh. A one-shot timer retries
at the cooldown deadline even when the normal preset is 30 minutes.

Transient failures retain readings only for the same account and until each known reset time. Error
messages remain visible beside retained readings, including real zero. Claude terminal login failures
clear the readings; Codex auth failures retain unexpired readings with an error, as in the Mac source.
Successful, identified readings are saved in `quota-history.json` inside the current data profile.
History is separated by provider, account, model group, and metric; each series retains up to 1,000
observations from the last seven days. The file is bounded to 16 accounts, 128 series, and 16 MiB.
Errors and missing values do not add samples. A successful response replaces the saved current window
set, including explicitly missing values, so restart cannot resurrect an omitted limit.

Before the first network request, read-only current credential identity can unlock that account's
saved readings. The interface labels the restored state while refreshing. Values expire at their
known reset time or window duration, whichever comes first; an unknown duration and reset cannot
produce a seeded reading. Antigravity's project identity and Codex's non-file backend are not known
before a successful account request, so those paths do not pre-seed. A different or unknown account
cannot inherit saved readings. Saved values can tint an alert but cannot pulse; the provider's first
live response establishes its own alert baseline without suppressing another provider's crossings.

The live sparkline plots actual stored observations with the Mac source's point spacing, line width,
fill, baseline, and endpoint treatment. Used and remaining modes share the same stored percentages.
With fewer than two observations it says **Collecting history**; without an account identity it says
**History unavailable**. This intentionally differs from the Mac's decorative fallback curve before
six samples. Corrupt files are preserved before replacement, newer schemas remain read-only, and
save failures leave current readings usable with a visible history warning. The file contains no
credentials or reset-credit payload. Local token/cost history uses the separate ledger in [HISTORY.md](HISTORY.md).

Live mode never displays fixture cost, token history, model breakdowns, calendar contributions, reset
credits, or generated quota sparkline curves. Cost, Overview, and cards now use local recorded history.
With no history evidence, those views remain unavailable and cannot export a demo card. Plan-comparison
bars use a known returned plan or show an unavailable reference; they do not inherit a sample plan.
Quota settings and account state are separate from the durable local cost history.

## Verification and limits

On 2026-09-12, the installed Windows ARM64 app's own installer buttons installed all four CLIs.
Codex CLI 0.154.0 and Antigravity CLI 1.2.2 completed user sign-in and returned live usage in the
running application (`f61ca8c6-928e-454f-a7df-814f576fbd91`, demo disabled). This establishes actual
Codex and Antigravity connections. Claude installation completed; its user login remains unverified.
Grok's official x64 1.0.30 executable stays running and opens its sign-in flow, whereas the native
ARM64 version crashed. The production compatibility preparation verified that the native executable
was unchanged and that the registered x64 executable was selected; real Grok quota is still unverified.

`tests/check-connected-account-setup.ps1` records each actual installation separately. All four account
buttons remain visible with only Codex and Antigravity selected on the island. Authentication-page
inspection records only a host, never an authentication URL, query, code, or token.

`tests/run-logic.ps1` passes 350 checks. These cover credential reads, exact request routes/headers/bodies,
missing/zero values, grouped metric selection, account changes, CLI renewal, credential metadata,
rotation, cooldowns, expiry, cancellation, history provenance, and Grok compatibility invalidation.
The native credential test uses its own temporary fixture item and deletes only that fixture. Account
protocol coverage includes the read-only method sequence, incompatible accounts, malformed responses,
bounded/flooded streams, cancellation, capped/missing credit details, and real `.ps1`/`.cmd` subprocess
launchers in paths containing spaces and apostrophes.
Quota cases cover persistence, account/group isolation, expiry, missing versus zero, file bounds,
corruption recovery, restart before a network response, cancellation, and mixed saved/live alerts.

`tests/run-live-render.ps1 -MacQuota <snapshot>` passes 75 WPF checks, including provider success/failure,
free/missing metrics, real settings buttons and menus, account-scoped metric persistence, history,
card provenance, and retention after source deletion/restart. These fixture checks complement the
real Codex/Antigravity connections; they do not establish real Claude/Grok authentication.
The reset-panel checks drive the real Windows pointer, cross the hover gap, dismiss and reopen the
panel, exercise keyboard/reduced-motion/localized/left-provider states, and remove an open panel when
credits become unavailable. The native render report records build `b652fb5c-fb33-4171-9ce9-678816987f2d`.
Six quota-history checks load saved observations into the real WPF surface and verify the used and
remaining curves, offline status, and missing-current-value behavior. Three additional checks replay
a frozen 1,000-point Mac weekly series without substituting samples and verify both native curves.
The reference renderer invokes the actual Mac `SparkSVG` source. The copied series is an isolated
test fixture; it is not assigned to the current Windows account's history.
The CLI bridge separately returned quota and reset-credit details for the signed-in Windows account
using Codex CLI 0.154.0. This verifies an actual CLI account read without changing its storage mode;
separate real keyring/encrypted account provisioning remains unverified.
`tests/check-codex-reset-ui.ps1` also verified the installed isolated preview
(`2f26e61a-b0b3-4862-b701-70eb96d89f1b`) using its signed-in account and imported Mac history. The live
badge, first hover after expansion, moving into the panel, Escape leaving the island expanded, and
reopening all passed. This caught an initial-entry bug that the standalone surface test did not cover:
the first move could arrive before the overlay stopped accepting clicks through it. The existing native
pointer tracker now synchronizes reset hover as the overlay becomes interactive.
`tests/check-quota-profile.ps1 -Restart` observed cached launch state, a successful live response,
and preservation of the prior quota observation in the separate profile on build
`cd9dab0a-69ec-4443-a66d-552e6bd9a2ca`, immediately before that pointer correction.
`tests/check-live-ui.ps1` previously passed 15 installed-app checks with isolated missing credentials.
Reports record the executable build identifier under ignored `artifacts/` and apply to that build.

Early image previews appeared to omit unchanged logos and text while accessibility checks still passed.
The harness now includes layered windows, synchronizes the render test with the compositor, and checks
visible logo pixels. Hardware and software runs passed; a VM-native capture showed the complete panel.
Independent decoding of the saved PNGs found 664/657 visible, fully opaque pixels in the two logo regions.
A byte-identical copy under a fresh filename displayed the complete panel while the original filename's
preview still appeared incomplete. This identifies a preview-path discrepancy for the current files,
rather than missing pixels in those saved captures. No production rendering change was made.
`-Software` and `-HoldCapture` remain test-only diagnostic options. Relevant APIs are
[BitBlt](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-bitblt),
[DwmFlush](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmflush), and
[WPF rendering preferences](https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.renderoptions.processrendermode).

The installed-app integration report records build `62275d02-866e-4431-afd9-325544387444`; the separately
built history-render harness records `b5e4356e-16ff-465e-8f67-7f2aafb34082`. The 15 hover/focus/click-through
checks also passed after history and swipe integration. Its five-second hidden sample used 15.625 ms of
CPU time, a separate VM observation rather than evidence of a performance improvement. Reports describe
the builds on which they ran, not every later build.

Wake recovery now cancels interrupted fetches and gives automatic requests a 60-second grace period.
Native network availability changes trigger a fresh request after reconnection, without resetting the
regular polling cadence or bypassing cooldowns. The 29 scheduling regressions cover interrupted
requests, per-provider credential recovery, duplicate events, and manual refresh behavior. A native
Windows event check exercised the power-event handler with targeted test messages; it was not physical
sleep. Disconnecting and reconnecting the VM's network adapter independently produced a fresh real
Codex reading before the next regular poll, and the adapter was restored afterward.

Remaining provider work includes Claude's CLI-owned renewal ping and pre-seeding
for CLI-backed/project-scoped identities, and direct recovery from Claude statistics files. Imported Mac history,
portable backup/restore, local persistence, and history-backed cards are implemented and verified in
[HISTORY.md](HISTORY.md). Real Claude/Grok login, restart/startup, actual rate-limit timing, and
account-switch flows still need Windows verification. Typography, effects, frame pacing, physical
devices, packaging, and update delivery remain tracked in [PARITY.md](PARITY.md).

`tests/check-dropdowns.ps1` additionally passes 18 installed-app checks for menu presentation, checked
state, keyboard/mouse dismissal and selection, the demo-to-live account action, CLI-button discovery,
remembered live mode on an ordinary launch, and returning to demo. Credentials are isolated and missing;
the test does not start either CLI or authenticate an account. Preferences, mode, and an existing startup
entry are restored afterward.
The final menu/account report records build `3cf7529d-52c6-4925-ba48-4f397243b849`.
