# CodexIsland

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>


> Your AI usage limits, living in your notch.

CodexIsland is a native macOS overlay that turns the MacBook notch into a
Dynamic-Island-style live activity for Claude Code and Codex usage limits. It
sits quietly over the notch, peeks on hover with the 5-hour headline, and
expands on click to show both providers' 5-hour and weekly windows with reset
timing, chart controls, and a small settings surface.

https://github.com/user-attachments/assets/195beeff-0f70-4d6b-8f3d-9f31d9c0b989


The app is free, open source, unsigned, and local-first. It reads credentials
already written by Claude Code / Claude Desktop and Codex, then calls only the
providers' own usage endpoints.

## What it does

- **Two providers, four windows.** Claude 5h + 7d and Codex 5h + 7d live in
  one panel.
- **Notch-native overlay.** The compact state is a black pill aligned to the
  physical notch. On non-notched Macs it falls back to a 200 x 28 menu-bar
  pill.
- **Hover to peek.** The silhouette widens just enough to show each visible
  provider's 5-hour percentage and reset headline.
- **Click to expand.** Click the island to open the full Usage / Cost panel,
  provider columns, and chart controls.
- **Click-through outside the island.** The window ignores mouse events outside
  the visible silhouette so the menu bar and apps underneath still work.
- **Five chart styles.** Ring, Bar, Stepped, Numeric, and Sparkline. Pick the
  default in Settings or Cmd-click the expanded panel to cycle.
- **Settings without a Dock icon.** A quiet gear in the expanded panel opens a
  custom settings window for launch-at-login, refresh interval, provider
  visibility, chart style, links, and Quit.
- **Configurable safe polling.** Choose 5m, 15m, or 30m. The app does not offer
  sub-5-minute polling because Anthropic rate-limits the usage endpoint
  aggressively.
- **Universal binary.** `build.sh` compiles arm64 and x86_64 slices and merges
  them with `lipo`, targeting macOS 13+.
- **Auto-updates via Sparkle.** The app checks the appcast attached to the
  latest GitHub Release on launch and once a day thereafter, then prompts
  before installing. Updates are signed with an EdDSA key — verifiable
  without involving Apple's signing infrastructure. Toggle off in Settings
  if you'd rather pin a version.
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

Download `CodexIsland-X.Y.Z.dmg` from
[Releases](https://github.com/ericjypark/codex-island/releases), drag the app
to `/Applications`, then run:

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
- CodexIsland tries `CLAUDE_CODE_OAUTH_TOKEN`, then the macOS Keychain item
  named `Claude Code-credentials`, then a refresh against Anthropic's OAuth
  token endpoint.
- If none work, the panel shows `auth required — run claude`.

The first fetch starts at app launch so the panel usually has values ready by
the first peek. Opening Settings also triggers a fresh fetch.

## Using the app

- Hover the notch to peek at the current 5-hour usage.
- Click the island to expand the full panel.
- Move away to collapse it.
- Cmd-click the expanded panel to cycle chart styles.
- Click the gear in the lower-left corner of the expanded panel to open
  Settings.
- Use Settings to enable Launch at Login, pick a refresh interval, hide/show
  Claude or Codex, choose the default chart style, open GitHub / License, or
  quit the app.

Provider visibility is display-only. Hiding a provider removes that provider's
logo and column from the island, but the app keeps the latest usage values in
memory so showing it again does not require a reset.

## Settings

Settings is a custom `NSWindow`, not the system Settings scene. The app still
runs as an accessory app with no Dock icon and no menu bar.

Stored preferences:

| Setting | Store | UserDefaults key | Values |
| --- | --- | --- | --- |
| Chart style | `StylePref` | `MacIsland.chartStyle` | `ring`, `bar`, `stepped`, `numeric`, `spark` |
| Style hint seen | `StylePref` | `MacIsland.hasCycledStyle` | Boolean |
| Refresh interval | `RefreshIntervalStore` | `MacIsland.refreshInterval` | `300`, `900`, `1800` |
| Claude visible | `ProviderVisibilityStore` | `MacIsland.claudeVisible` | Boolean, default `true` |
| Codex visible | `ProviderVisibilityStore` | `MacIsland.codexVisible` | Boolean, default `true` |
| Launch at login | `LaunchAtLoginStore` | managed by `SMAppService.mainApp` | System login item status |

The refresh interval applies live. `UsageStore` invalidates the current timer
and re-arms it with the selected cadence.

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
./scripts/verify.sh
```

The script builds the app, launches the binary for one second, then kills it if
it is still alive.

## Release

Package a DMG:

```sh
npm install --global create-dmg
./release.sh
```

`release.sh` runs the native build, copies the `.app` to `dist/`, applies ad-hoc
codesigning, creates `dist/CodexIsland-X.Y.Z.dmg`, and prints the file size and
SHA-256.

Pushing a `v*` tag triggers `.github/workflows/release.yml` on `macos-15`,
builds the DMG, computes the checksum, publishes a GitHub Release, and mirrors
the cask to `ericjypark/homebrew-tap` when `HOMEBREW_TAP_TOKEN` is configured.

`Casks/codexisland.rb` is the Homebrew Cask template. Do not manually bump its
version or SHA for normal releases; CI copies it to the tap and rewrites those
fields from the tag and freshly built DMG.

## Repository layout

```text
.
├── Sources/
│   ├── App.swift
│   ├── Model/
│   ├── Theme/
│   ├── Usage/
│   ├── Views/
│   └── Window/
├── Resources/              # App-bundled logo PNGs and .icns
├── Assets/                 # README logo asset
├── landing/                # Next.js marketing site
├── docs/superpowers/specs/ # Design specs for recent UI work
├── Casks/                  # Homebrew Cask template
├── scripts/verify.sh       # Native smoke test
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
- Codex tokens are read locally from `~/.codex/auth.json`.
- Claude tokens are read from `CLAUDE_CODE_OAUTH_TOKEN`, the macOS Keychain, or
  Anthropic's refresh endpoint.
- Tokens leave the machine only as `Authorization` headers to `chatgpt.com` and
  `api.anthropic.com`.

The network surface is concentrated in
[`Sources/Usage/UsageFetcher.swift`](Sources/Usage/UsageFetcher.swift).

## Troubleshooting

**Claude shows `auth required — run claude`.**
Run `claude` once in Terminal or open Claude Desktop so the credentials exist.

**Codex shows `no codex auth`.**
Sign in to Codex / ChatGPT CLI and confirm `~/.codex/auth.json` exists.

**The app shows stale values after an error.**
That is intentional. `UsageStore` keeps the previous good values when a refresh
returns only errors, so a temporary 429 does not turn the panel into 0%.

**Why can I not choose 30-second polling?**
Anthropic rate-limits `/api/oauth/usage` per token. The app exposes 5m, 15m,
and 30m only.

**Does it work without a notch?**
Yes. It falls back to a 200 x 28 pill in the menu-bar area.

**Does it support multiple monitors?**
Partially. The app prefers the first display whose safe-area inset indicates a
notch, then falls back to `NSScreen.main`. Multi-monitor setups still get one
island, not one island per display.

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
- Sparkline history is synthesized, not provider-sourced history.
- Multi-monitor placement uses a single island.
- Accessibility is partial: VoiceOver labels exist, but a high-contrast variant
  is not implemented yet.

## Acknowledgements

- [codexbar](https://github.com/steipete/codexbar) by Peter Steinberger -
  auth-source archaeology for the Claude env-var -> keychain -> refresh ladder.
- [claudecodeusage](https://github.com/RchGrav/claudecodeusage) by Rich Hickson
  - the `claude-code/2.1.121` User-Agent requirement on `/api/oauth/usage`.
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
  by Sindre Sorhus - reference shape for `SMAppService.mainApp`.
- [Emil Kowalski](https://animations.dev) - animation timing and interaction
  discipline.

## License

MIT - see [LICENSE](LICENSE).

<a href="https://www.star-history.com/?type=date&repos=ericjypark%2Fcodex-island">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ericjypark/codex-island&type=date&legend=top-left" />
 </picture>
</a>
