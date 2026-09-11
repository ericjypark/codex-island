# Changelog

User-facing changes per release. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); dates are when the
tag was cut.

## [0.2.4] - 2026-09-08

### Fixed

- Antigravity quota now uses the agy CLI backend, correcting readings stuck at
  100% remaining while the CLI reports usage.
- Grok reads weekly and monthly subscription allowances without substituting
  on-demand spending caps for subscription usage. Missing readings stay unknown.
- Overview labels small nonzero provider shares as `<1%` instead of `0%`.

## [0.2.3] - 2026-09-08

Large cost totals are easier to read: the main numbers now use digit grouping
such as `1,964,040`, including during the count-up animation. Separators follow
the app's locale, and the full amount still scales to fit its tile.

## [0.2.2] - 2026-09-08

View estimated token costs in your preferred currency, with nine display
currencies and cached daily exchange rates.

### Added

- Choose USD, CNY, EUR, GBP, JPY, KRW, CAD, AUD, or CHF in Settings → Providers.
  Cost totals, value comparisons, and model breakdowns use the selected currency;
  underlying model prices stay in USD. Offline, the last valid exchange rates
  are retained, with a clearly labeled USD fallback before rates are available.

### Fixed

- Large converted amounts scale to fit the cost tile instead of truncating digits.
- The expanded panel fits the selected page's content, including calendar day
  details, and settles at the correct height after rapid navigation during opening.
- The entire Usage display row in provider settings now opens its controls.

## [0.2.1] - 2026-09-08

See every supported provider's activity in one calendar, then click a provider
in the legend to filter its history—even when it is not selected for the usage pills.

### Changed

- Overview combines local history from all supported providers and adds provider filters.
- Page transitions use Core Animation, with display-aware frame pacing and a
  30 FPS request in Low Power Mode. History preparation avoids repeated work
  during interaction updates.
- Antigravity has a distinct lilac color, and Settings opens with more vertical space.

### Fixed

- Expired Grok and Antigravity sessions get one renewal attempt through the
  official CLI before retrying. HTTP 403 no longer implies that the user is logged out.
- Accounts without reported usage show actionable empty states; existing cost
  records and real zero-percent readings remain visible.

## [0.1.23] - 2026-08-14

Weekly-only Codex plans get a real number in the peek pill instead of "—%".

### Fixed

- **The peek pill works on weekly-only Codex plans.** Plans that report
  only a weekly quota (no 5-hour window) always showed "—%" on hover —
  the pill was hard-wired to the missing 5-hour slot. It now falls back
  to the weekly window: the remaining percentage and its multi-day
  countdown ("34% · 6d 23h") render, VoiceOver announces it as the
  weekly window, and the no-countdown fallback glyph reads "7d" instead
  of "5h". Two-window plans still show the 5-hour window first.
  Contributed by @albertloky (#75).
- **Limit alerts follow the window you can see.** Alert severity (the
  warning glyph and amber/red tint) tracked the 5-hour window even when
  the peek was showing the weekly one — a weekly-only plan at 96% never
  warned. Severity now tracks the same window the pill displays.

## [0.1.22] - 2026-08-10

Waking your Mac no longer strands the Claude card on "rate limited" or
"token expired — run claude", and the Codex week tile is alive again.

### Fixed

- **Post-wake false alarms self-heal now.** Opening the lid used to fire
  the first poll straight into a half-up network with an access token
  that had expired mid-sleep — the panel then sat on an error caption
  for up to 45 minutes even though Claude itself worked fine. The app
  now waits out the wake burst before its first probe, watches the
  credential store for Claude Code's own token refresh and refetches
  within seconds (metadata only — never a keychain prompt), nudges the
  CLI with one silent haiku ping per expiry episode on days when
  nothing else refreshes the login (desktop-app-only workflows), and
  repaints the last real readings under the failure caption instead of
  blanking to "—" while a rate-limit cooldown runs its course.
- **The Codex week tile had been dead since mid-July.** The usage API
  stopped assigning window slots by position: single-limit plans now
  ship their weekly window in the primary slot, which landed the weekly
  percentage in the 5h tile (complete with a "resets in 3d" countdown)
  and left the week tile at "—" forever. Windows are now routed by
  their advertised span, with the old slot-order behavior kept for
  accounts still on the two-window shape.
- **No more fabricated percentages.** A window the plan doesn't report
  shows a passive "—" everywhere now — the peek pill used to render it
  as "0% · 5h" (a full budget under the remaining toggle) and Settings
  flagged it "⚠ no data" as if something were broken.

## [0.1.21] - 2026-07-26

Model prices now come from a published catalog instead of the app binary,
so a new model no longer waits on an app release to price correctly.

### Changed

- **New models price themselves.** Until now every new model needed a
  CodexIsland release before its cost showed up — in the gap, its turns
  counted as tokens but totalled $0. Prices now come from a public
  [catalog][catalog] the app refreshes once a day, and it already carries
  78 models, including many this app has never shipped a price for. The
  request sends no identifier and no usage data; if it fails, the app
  keeps using its last good copy, and failing that the table baked into
  the build. Your totals cannot go blank because the fetch went wrong.
- **The "pricing data N days old" note in Settings is gone.** It existed
  to warn that a frozen price table had drifted, which was worth saying
  when the only fix was updating the app. With prices refreshing on their
  own it was a warning about nothing the reader could act on.

[catalog]: https://github.com/ericjypark/codex-island-model-catalog

## [0.1.20] - 2026-07-26

A one-line pricing fix, shipped on its own so heavy Opus 5 users stop
under-counting today.

### Fixed

- **Claude Opus 5 now prices.** Sessions on the new model were counted as
  tokens but priced at $0, so the Cost screen showed an `⚠ 1 unpriced`
  badge and a dollar total that was short by every Opus 5 turn. Opus 5
  bills in the same re-tiered Opus band as 4.5–4.8 ($5 / $25 per million
  input / output). Note that Opus 5's *fast mode* bills at a premium
  Claude Code doesn't record in its session logs, so — as with `ccusage`
  — those turns are still counted at the standard rate.

## [0.1.19] - 2026-07-22

The stop-nagging-me release: no more macOS keychain password popups, and no
more false "Claude session expired" panels.

### Fixed

- **macOS keychain password prompts are gone.** Clicking "Always Allow"
  never stuck because Claude Code's ~8h token rotation rewrites its
  keychain item in a way that silently wipes per-app grants (the item's
  partition list resets to `apple-tool:`). CodexIsland now reads the
  credential through Apple's `security` tool, which that rewrite
  permanently trusts — so reads are silent on every Mac, across every
  update, with no Apple Developer certificate required.
- **"Claude session expired" no longer appears while you're actually
  logged in.** The app held a copy of the access token in memory past
  Claude Code's rotation; when the copy expired it flashed the re-auth
  panel for up to a full poll interval even though a fresh token was
  already in the keychain. A failed token now triggers an immediate
  re-read and retry in the same pass — the panel only appears when the
  login is genuinely dead.
- **Logins under a custom `CLAUDE_CONFIG_DIR` are now found.** Claude Code
  stores those under a hashed keychain service name; the app now discovers
  credential items by enumerating keychain metadata instead of assuming
  the default name.
- **The re-auth panel now says "Claude re-login needed"** when the token is
  missing a required scope (the fix is `claude /login`), keeping "session
  expired" for genuine expiry. Localized in English and Chinese.
- **The one-click Re-authenticate flow is quieter and sturdier.** It waits
  for the login to actually write credentials before touching the keychain
  (previously up to 24 reads per re-auth), recovers from a transient
  network failure right after login, and backs off immediately when the
  usage API rate-limits.

## [0.1.4] - 2026-05-09

A polish + hardening release. One user-visible fix in Settings; the rest
is interior work — perf, refactor, and three release-pipeline guardrails
that exist so a botched future release doesn't silently brick auto-update.

### Fixed

- **Settings → Providers now shows auth errors instead of `0%`.** When
  Claude or Codex can't be reached (auth missing, expired, rate-limited),
  the row used to render `synced 2m ago · 0% / 0%` — the most authoritative
  diagnostic surface in the app silently masked the real reason. It now
  shows `⚠ auth required — run claude` (or whichever error fired) in place
  of the `0%`, per window.

### Internal

- **`IslandRootView` decomposed.** The root view used to observe seven
  stores; any `@Published` emission re-evaluated the whole tree, including
  every overlay and gesture closure. Split into `GlowLayer`, `LogoOverlay`,
  and `PeekPillOverlay` children, each subscribed to only what they read.
  Up to 8 redundant body re-evals per poll cycle eliminated.
- **`AppEnvironment` centralizes mode flags.** `CODEXISLAND_DEMO` /
  `CODEXISLAND_DEBUG` were checked across eight files via raw
  `ProcessInfo.processInfo.environment["..."]` lookups. Resolved once at
  launch into a typed enum (`AppEnvironment.isDemo`, `.isDebug`); a typo in
  any one literal can no longer silently miss the mode.
- **Generic `LogParseCache<Event>` shared by both log readers.**
  `ClaudeLogReader` and `CodexLogReader` previously duplicated ~70-80% of
  their cache + file-walk scaffolding. Extracted to one generic. Net
  −218 LOC across the two reader files. As a behavioral side effect, the
  Codex reader now uses the same 64 KB chunked streaming reader as Claude,
  closing a peak-RSS spike during 30-day rollout scans. Cache JSON shape
  is byte-identical, so existing caches survive the upgrade.

### Release pipeline

These all guard against silent bricks of Sparkle auto-update or the
Homebrew cask. None affect the running app — but if any one of them ever
fires, you'll get a loud failure at release time instead of a silently
broken update channel weeks later.

- **`build.sh` and `release.sh` reject non-semver `VERSION`.** A
  `VERSION` of `1` or `1.0` parses as `[1]` under Apple's component-wise
  comparator, which is *larger* than `0.0.99` — Sparkle would never offer
  any update to the affected installs. Tagging now fails loud at
  `error: VERSION must be X.Y.Z`.
- **`release.sh` aborts on empty EdDSA signature.** `set -euo pipefail`
  doesn't catch a zero-exit with malformed `sign_update` output. An
  appcast with `sparkle:edSignature=""` is rejected silently by every
  Sparkle client. The release now fails before the appcast is written.
- **CI uses an explicit DMG path for SHA-256.** A glob that matched no
  files would silently produce an empty SHA, which then `sed`'d into the
  Homebrew cask without changing it — `brew install` mismatched on every
  user. The path is now derived from the tag and existence-checked.
- **`build.sh` propagates Sparkle XPC codesign failures.** Previously
  swallowed via `2>/dev/null || true`, surfacing only at the user's first
  Check Now click as "The updater failed to start." The path-existence
  guard kept the original "tolerate missing helpers" behavior; real
  signing errors now fail the build.

## [0.1.0] - 2026-05-05

Three changes on top of the 0.0.10 baseline. The minor-version bump signals
that the 0.0.x bootstrap series is over — not that this single release is
big. Per-tag detail for the 0.0.x series lives on the
[GitHub Releases page](https://github.com/ericjypark/codex-island/releases).

### Added

- **Token counting toggle.** Settings → Providers → Tokens picks between
  *All tokens* (input + output + cache_creation + cache_read — ccusage
  parity, the prior default and the only mode in 0.0.x) and *Input + output*
  (matches Anthropic's claude.ai stats panel, which excludes cache reads).
  Both totals are computed every scan and cached, so flipping the segment
  is instant — no rescan.
- **`CHANGELOG.md`.** Going forward, each release ships with a curated
  user-facing changelog in this file.

### Changed

- **Continuous (squircle) corners on the island silhouette.** Replaces the
  hand-rolled circular-arc + straight-line path with
  `UnevenRoundedRectangle(style: .continuous)`, eliminating the small kink
  at the tangent point that was visible against the hardware notch.
- **Peek pill always shows window context.** When a provider didn't return
  an active `resetAt`, the pill used to drop the separator and render bare
  percentage — making the layout shift between hovers. It now always renders
  `<percent> · <label>`. With an active countdown the label is the live time
  remaining at full opacity; otherwise it falls back to the window length
  (`5h`) at reduced opacity, so countdown vs. passive label stays visually
  distinct without changing geometry.

### Internal

- `MacIsland.costCache.v2` → `v3`. First launch on 0.1.0 backfills the
  billable-tokens column with one fresh local-log scan; existing dollar +
  total-tokens rollups remain valid.
