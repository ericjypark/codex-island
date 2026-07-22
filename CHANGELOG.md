# Changelog

User-facing changes per release. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); dates are when the
tag was cut.

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
