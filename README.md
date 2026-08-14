# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

<p align="center">
  <a href="https://hits.sh/github.com/ericjypark/codex-island/">
    <img alt="README visitors" src="https://hits.sh/github.com/ericjypark/codex-island.svg?label=visitors&color=007ec6&labelColor=555555">
  </a>
</p>

> Your AI usage limits, living in your notch.

CodexIsland is a native macOS overlay that turns the MacBook notch into a
Dynamic-Island-style live activity for Claude Code and Codex usage limits. It
sits quietly over the notch, peeks on hover with the 5-hour headline, and
expands on click to show both providers' 5-hour and weekly windows with reset
timing, chart controls, local-log cost estimates, and a year-at-a-glance usage
history.

https://github.com/user-attachments/assets/195beeff-0f70-4d6b-8f3d-9f31d9c0b989


The app is free, open source, unsigned, and local-first. It reads credentials
already written by Claude Code / Claude Desktop and Codex, then calls only the
providers' own usage endpoints.

## What it does

- **Two providers, four windows.** Claude 5h + 7d and Codex 5h + 7d live in
  one panel.
- **Notch-native overlay.** The compact state is a black pill aligned to the
  physical notch, drawn with continuous (squircle) corners that match the
  hardware. On non-notched displays it falls back to a configurable menu-bar
  pill.
- **Hover to peek.** The silhouette widens just enough to show each visible
  provider's 5-hour percentage and reset headline, or keep those headlines
  visible at rest with **Always show usage**.
- **Three swipeable screens.** Click to expand, then swipe between **Usage**,
  **Cost**, and **Overview**. Cost estimates today and month-to-date spend and
  token throughput from local Claude Code, Codex CLI, and OpenCode session
  data. Overview renders the current year's activity as a contribution-style
  calendar.
- **Used or remaining quota.** Display provider windows as usage consumed or
  quota remaining.
- **Approaching-limit alerts.** Optional warning and critical thresholds tint
  the island and pulse the peek pill as a visible 5-hour window nears its
  limit.
- **Codex reset credits.** When reset credits are available, the Usage footer
  shows their count and expiration details.
- **Configurable token counting.** The TOKENS hero can sum every token type
  that crossed the wire (cache included, ccusage parity) or input + output
  only — the latter matches Anthropic's claude.ai stats panel.
- **Click-through outside the island.** The window ignores mouse events outside
  the visible silhouette so the menu bar and apps underneath still work.
- **Five chart styles.** Ring, Bar, Stepped, Numeric, and Sparkline. Pick the
  default in Settings or Command-click the expanded panel to cycle. Sparkline
  uses real readings recorded by CodexIsland during successful refreshes.
- **On-demand refresh.** Click `synced Xs ago` in the panel header to refetch
  immediately; the next scheduled poll re-arms from there.
- **Cobalt glow + Low Power Mode.** A soft glow around the island signals an
  in-flight refresh. Low Power Mode hides the steady-state glow so it only
  pulses during active work.
- **Settings without a Dock icon.** A quiet gear in the expanded panel opens a
  custom, resizable settings window with General, Display, and Providers tabs.
- **English and Simplified Chinese.** Follow the macOS language automatically
  or choose a language in Settings.
- **Display selection.** Auto-pick a notched display or pin the island to a
  specific connected display. Non-notched displays offer compact and
  notch-style widths.
- **Configurable safe polling.** Choose 5m, 15m, or 30m. The app does not offer
  sub-5-minute polling because Anthropic rate-limits the usage endpoint
  aggressively.
- **Universal binary.** `build.sh` compiles arm64 and x86_64 slices and merges
  them with `lipo`, targeting macOS 13+.
- **Auto-updates via Sparkle.** The app checks the appcast attached to the
  latest GitHub Release in the background, then prompts before installing.
  Updates are signed with an EdDSA key — verifiable without involving Apple's
  signing infrastructure. Toggle off automatic checks in Settings if you'd
  rather pin a version.
- **Native app privacy.** No app telemetry, no crash reporting, no third-party
  app analytics, and no proxy service.

## Install

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

The first invocation auto-taps `ericjypark/homebrew-tap`. The cask strips the
Gatekeeper quarantine attribute automatically (CodexIsland is unsigned by
Apple — Sparkle handles update verification independently).

### Direct download

Download the current `CodexIsland-X.Y.Z.dmg` from the
[latest release](https://github.com/ericjypark/codex-island/releases/latest),
drag the app to `/Applications`, then run:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

<details>
<summary>Why is the dequarantine command necessary?</summary>

CodexIsland is unsigned because Apple charges $99/year for a Developer ID
certificate, and this is a free open-source project. The command removes the
macOS Gatekeeper quarantine attribute that triggers the "cannot be opened
because Apple cannot check it for malicious software" warning. The source code
is in this repository for audit.

If a sponsored Apple Developer ID becomes available via
[GitHub Sponsors](https://github.com/sponsors/ericjypark), signed builds can
follow.
</details>

<details>
<summary>I do not want to use Terminal. What do I do?</summary>

1. Drag `CodexIsland.app` to `/Applications`.
2. Try to open it. macOS will block it because the build is unsigned.
3. Open **System Settings -> Privacy & Security**.
4. Scroll to the bottom and find the blocked CodexIsland message.
5. Click **Open Anyway**, then re-launch the app.
</details>

## First run

CodexIsland does not ask for passwords or API keys. It reads the auth state
already created by the command-line tools or desktop apps you use.

For Codex:

- Sign in to Codex / ChatGPT CLI first.
- CodexIsland reads `~/.codex/auth.json`.
- If the file or access token is missing, the panel shows `no codex auth`.

For Claude:

- Run `claude` once, or open Claude Desktop, so Claude credentials are
  populated.
- CodexIsland checks `CLAUDE_CODE_OAUTH_TOKEN`, then
  `$CLAUDE_CONFIG_DIR/.credentials.json` (normally
  `~/.claude/.credentials.json`), then the macOS Keychain item named
  `Claude Code-credentials`.
- Credential access is strictly read-only. CodexIsland never refreshes OAuth
  tokens or writes to Claude's credential store; run `claude` when an access
  token expires, or `claude /login` when the endpoint requires a newly scoped
  token.
- If none work, the panel shows `auth required — run claude`.

The first fetch starts at app launch so the panel usually has values ready by
the first peek. Opening Settings also triggers a fresh fetch.

## Using the app

- Hover the notch to peek at the current 5-hour usage.
- Click the island to expand the full panel.
- Swipe horizontally on the panel (or use the indicator dots) to move between
  **Usage**, **Cost**, and **Overview**.
- Move away to collapse it.
- Command-click the expanded panel to cycle chart styles on the active screen
  (Usage cycles Ring/Bar/Stepped/Numeric/Sparkline; Cost cycles
  USD/VALUE/TOKENS/TREND; Overview has one calendar view).
- Click `synced Xs ago` in the panel header to refetch immediately.
- Click the gear in the lower-left corner of the expanded panel to open
  Settings, or press ⌘,.
- Press ⌘Q while the pointer is over the island to quit. You can also
  quit from Settings.

Provider visibility is display-only. Hiding a provider removes that provider's
logo and column from the island, but the app keeps the latest usage values in
memory so showing it again does not require a reset.

## Settings

Settings is a custom `NSWindow`, not the system Settings scene. The app still
runs as an accessory app with no Dock icon and no menu bar.

- **General:** Launch at Login, 5m/15m/30m refresh interval, app language,
  light/dark/system appearance, Always show usage, Low Power Mode,
  configurable limit alerts, and Sparkle update controls.
- **Display:** used/remaining percentages, Usage and Cost visualization styles,
  target display, and island width on non-notched screens.
- **Providers:** Claude/Codex visibility and status, token-counting mode, and a
  manual refresh for local cost data.

Preferences are stored in `UserDefaults` under `MacIsland.*` keys (Sparkle
manages its own `SU*` update keys, and Launch at Login uses
`SMAppService.mainApp`). Appearance, refresh, display, and provider changes
apply live; changing the app language offers to restart CodexIsland.

## Build from source

Requires macOS 13+ and a Swift toolchain from Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

There is no Xcode project and no SwiftPM package. `build.sh` runs `swiftc` over
`Sources/**/*.swift`, compiles arm64 and x86_64 slices, merges them with
`lipo`, copies bundled resources, and writes `Info.plist`.

Smoke test the native app:

```sh
./scripts/run-tests.sh
./scripts/verify.sh
```

`run-tests.sh` compiles and runs the credential-resolution and notch-height
test harnesses. `verify.sh` builds the app, launches the binary for one second,
then kills it if it is still alive.

## Release

Package a DMG:

```sh
npm install --global create-dmg
./release.sh
```

`release.sh` runs the native build, copies the `.app` to `dist/`, applies ad-hoc
codesigning, creates `dist/CodexIsland-X.Y.Z.dmg`, signs it with Sparkle's
EdDSA key when available, generates `dist/appcast.xml`, and prints the file size
and SHA-256.

Pushing a `v*` tag triggers `.github/workflows/release.yml` on `macos-15`,
builds the signed DMG and appcast, generates release notes from Conventional
Commits, publishes both artifacts in a GitHub Release, and mirrors the cask to
`ericjypark/homebrew-tap` when `HOMEBREW_TAP_TOKEN` is configured.

`Casks/codexisland.rb` is the Homebrew Cask template. Do not manually bump its
version or SHA for normal releases; CI copies it to the tap and rewrites those
fields from the tag and freshly built DMG.

## Repository layout

```text
.
├── Sources/
│   ├── App.swift
│   ├── Cost/                # Local-log cost + token aggregation
│   ├── Localization/        # Runtime localization helper
│   ├── Model/
│   ├── Theme/
│   ├── Update/              # Sparkle wrapper
│   ├── Usage/
│   ├── Views/
│   └── Window/
├── Resources/              # Icons, provider marks, localized strings
├── Assets/                 # README logo asset
├── Tests/                  # Bare-swiftc regression harnesses
├── docs/                   # Sparkle runbook, design specs
├── Casks/                  # Homebrew Cask template
├── scripts/                # Tests, native smoke test, Sparkle setup
├── build.sh                # Universal .app build
├── release.sh              # DMG packaging
└── VERSION
```

## Privacy

Native app behavior:

- No app telemetry.
- No app analytics.
- No crash reporting.
- No proxy server.
- No credentials are stored by CodexIsland.
- Model prices are fetched once a day from a public, GitHub-hosted catalog
  ([codex-island-model-catalog](https://github.com/ericjypark/codex-island-model-catalog)).
  The request carries no identifier, no token, and no usage data — it is a
  plain GET for a static JSON file, and the app works from a local cache when
  it fails.
- Codex tokens are read locally from `~/.codex/auth.json`.
- Claude tokens are read from `CLAUDE_CODE_OAUTH_TOKEN`, Claude's credentials
  file, or the macOS Keychain. CodexIsland never refreshes or writes them.
- Tokens leave the machine only as `Authorization` headers to `chatgpt.com` and
  `api.anthropic.com`.
- The Cost screen reads local Claude Code session logs from
  `~/.claude/projects/**/*.jsonl` (and `~/.config/claude/...`, plus any path
  in `CLAUDE_CONFIG_DIR`), Codex session logs from `~/.codex/sessions/`, and
  OpenCode data from `~/.local/share/opencode/`. Aggregation happens entirely
  on-device — no log content is uploaded or shared anywhere.

The visitor badge at the top of this README is an external `hits.sh` image that
counts badge requests. It is not bundled with or contacted by the native app.

The network surface is concentrated in
[`Sources/Usage/UsageFetcher.swift`](Sources/Usage/UsageFetcher.swift). The
local log readers live in [`Sources/Cost/`](Sources/Cost/).

## Troubleshooting

**Claude shows `auth required — run claude`.**
Run `claude` once in Terminal or open Claude Desktop so the credentials exist.

**Claude shows `token expired — run claude`.**
Run `claude` so Claude Code can refresh its own token. CodexIsland intentionally
does not refresh it.

**Claude shows `re-login: claude /login`.**
The stored token is missing a scope now required by the usage endpoint. Run
`claude /login` to mint a newly scoped token; refreshing the old token is not
enough.

**Codex shows `no codex auth`.**
Sign in to Codex / ChatGPT CLI and confirm `~/.codex/auth.json` exists.

**Codex shows `auth expired — codex login`.**
Run `codex login` to refresh the credentials in `~/.codex/auth.json`.

**The app shows stale values after an error.**
That is intentional. `UsageStore` keeps the previous good values when a refresh
returns only errors, so a temporary 429 does not turn the panel into 0%.

**Why can I not choose 30-second polling?**
Anthropic rate-limits `/api/oauth/usage` aggressively at the account level. The
app exposes 5m, 15m, and 30m only.

**Does it work without a notch?**
Yes. It falls back to a compact menu-bar pill; Settings can switch it to the
wider notch-style spacing.

**Does it support multiple monitors?**
Yes, with one island at a time. Auto mode prefers a notched display, then the
main display. You can also pin the island to a connected display in Settings;
if that display is unplugged, CodexIsland falls back to Auto.

**Will the usage endpoints break?**
Probably at some point. Both provider endpoints are undocumented. If the panel
starts showing parse errors or HTTP errors, open an issue with the response
shape and redact tokens.

**Why is there no Dock icon?**
CodexIsland is an accessory app. Use the gear in the expanded island to open
Settings, and use Settings -> Quit to exit.

## Known limits

- Unsigned builds require dequarantine / Open Anyway.
- Claude and Codex usage endpoints are undocumented.
- Sparkline history contains only readings CodexIsland records while it is
  running; providers do not expose historical usage series.
- Multi-monitor setups use one island, pinned to or auto-selected for one
  display at a time.
- Accessibility is partial: VoiceOver labels exist, but a high-contrast variant
  is not implemented yet.

## Acknowledgements

- [codexbar](https://github.com/steipete/codexbar) by Peter Steinberger -
  auth-source archaeology for Claude credential resolution.
- [claudecodeusage](https://github.com/RchGrav/claudecodeusage) by Rich Hickson
  - the `claude-code/2.1.121` User-Agent requirement on `/api/oauth/usage`.
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
  by Sindre Sorhus - reference shape for `SMAppService.mainApp`.
- [Emil Kowalski](https://animations.dev) - animation timing and interaction
  discipline.

## Changelog

See [GitHub Releases](https://github.com/ericjypark/codex-island/releases) for
current release notes and [CHANGELOG.md](CHANGELOG.md) for curated milestone
notes.

## License

MIT - see [LICENSE](LICENSE).

<a href="https://www.star-history.com/?type=date&repos=ericjypark%2Fcodex-island">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
 </picture>
</a>
