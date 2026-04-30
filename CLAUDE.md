# CLAUDE.md

Project-specific guardrails. **Read every section before touching this repo.**

## Release process — MANDATORY

This app ships via Sparkle auto-update. Get any of this wrong and you brick auto-update for everyone who's already installed.

### The loop (3 commands)

```sh
echo "X.Y.Z" > VERSION                                # 1. Bump
git commit -am "chore(release): bump VERSION to X.Y.Z" \
  && git tag vX.Y.Z                                   # 2. Commit + tag
git push origin main vX.Y.Z                           # 3. Push (fires CI)
```

That's it. CI does **everything else** in ~1.5 min:

- Builds the universal DMG
- Signs it with the EdDSA key from the `SPARKLE_ED_PRIVATE_KEY` secret
- Generates `appcast.xml` listing the new version
- Uploads DMG + appcast as release assets
- Mirrors the cask to `ericjypark/homebrew-tap` with the new version + SHA-256

Watch with `gh run watch --exit-status` if you want confirmation, or just trust it.

### Hard rules — break these and you brick auto-update

1. **`VERSION` must be a single-monotonic version like `0.0.X`, NOT `1` or `100` or anything weird.** `build.sh` uses `$VERSION` as both `CFBundleVersion` and `CFBundleShortVersionString`. Sparkle compares `CFBundleVersion` of the running app against `sparkle:version` in the appcast using Apple's component-wise comparator — so `"1"` parses as `[1]` and is **larger than** `"0.0.99"`. Stay in semver. Always increase.

2. **The Sparkle public key in `build.sh` (`SU_PUBLIC_KEY="bz1g..."`) must NEVER be changed casually.** Every existing install verifies updates against this exact key. Change it and every prior install rejects every future update silently. The matching private key lives in (a) the maintainer's macOS Keychain under service `https://sparkle-project.org` and (b) the `SPARKLE_ED_PRIVATE_KEY` GitHub Actions secret. To rotate, see the migration note in `docs/SPARKLE.md` (TL;DR: don't).

3. **Don't manually edit `Casks/codexisland.rb` for a version bump.** CI rewrites it on the homebrew-tap side at release time. Manual version/SHA edits are overwritten or drift. (Editing unrelated cask metadata — postflight, zap, livecheck — via a normal commit is fine; CI preserves those.)

4. **Never edit appcast XML files by hand.** The appcast is a release asset built by `release.sh` from the signed DMG. Hand-edits invalidate the EdDSA signature.

5. **Never commit `Vendor/`.** It's gitignored. The `bin/sign_update`, `bin/generate_keys`, etc. binaries live there for local use; CI re-vendors via `scripts/setup-sparkle.sh`.

### CI secrets (one-time, already configured)

These two GitHub Actions secrets exist on the `codex-island` repo:

- **`SPARKLE_ED_PRIVATE_KEY`** — the EdDSA private key. Without it CI fails at the signing step.
- **`HOMEBREW_TAP_TOKEN`** — fine-grained PAT with `contents: write` on `ericjypark/homebrew-tap` only. Without it the cask-sync step warns and skips, but the GitHub Release still ships.

If either is rotated, regenerate via the original instructions in `docs/SPARKLE.md`.

### Smoke-testing the update prompt locally

If you want to verify Sparkle's UI before tagging:

```sh
./release.sh                  # produces dist/CodexIsland-X.Y.Z.dmg + dist/appcast.xml
                              # (uses Keychain key — no env vars needed locally)
```

The local `release.sh` is identical to CI except for asset upload. To force-trigger an update prompt without publishing: temporarily change `SUFeedURL` in `build.sh` to point at `http://127.0.0.1:8765/appcast.xml`, serve `dist/appcast.xml` from there with `python3 -m http.server 8765`, run with a lower local `VERSION` than the appcast advertises, hit Check Now.

To build with auto-update **disabled** (debug copies): `SU_FEED_URL= ./build.sh`.

### Things that have already broken and how they were fixed

History — read before re-stepping on these rakes:

| Problem | Symptom | Root cause | Fix |
|---|---|---|---|
| `CFBundleVersion = "1"` hardcoded | Sparkle never sees any update as newer | `"1"` > `"0.0.X"` in component-wise comparison | `build.sh` now sets it to `$VERSION` |
| `SUPublicEDKey` empty in CI builds | Sparkle silently rejects every signed update | Public key was in gitignored `Vendor/` only | Public key hardcoded in `build.sh` |
| `xattr -d` non-recursive in cask postflight | "Updater failed to start" on first Check Now | Quarantine attr remained on Sparkle's nested `Updater.app` | `xattr -dr` (recursive) |
| `--no-quarantine` in install docs | `brew install` fails with "switch is disabled" | Homebrew removed the flag in late 2025 | Cask postflight strips the attr; flag removed from docs |
| `…` after `$VAR` in shell scripts | CI fails with `unbound variable` | Non-UTF-8 locale on runners makes bash include trailing bytes in identifier | Use `${VAR}…` braces, or stick to ASCII in echo strings |
| Old yonsei email in commits | Vercel rejected landing deploys | Local git config used unverified email | Set `git config user.email` to a GitHub-verified address before committing |

## Architecture pointers

- `Sources/Window/IslandWindowController.swift` — borderless overlay window. Listens to `NSApplication.didChangeScreenParametersNotification` to reposition on display changes; prefers the screen with `safeAreaInsets.top > 0` (the notched display).
- `Sources/Update/UpdaterController.swift` — wraps Sparkle's `SPUStandardUpdaterController`. Reads `SUFeedURL` / `SUPublicEDKey` from Info.plist (injected by `build.sh`). Auto-check state is stored by Sparkle itself in `NSUserDefaults` under `SU*` keys.
- `Sources/Usage/UsageFetcher.swift` — Codex (`/wham/usage`) and Claude (`/api/oauth/usage`) fetchers. Claude requires the `claude-code/X.Y.Z` User-Agent + `oauth-2025-04-20` beta header. Refresh-token rotation is wired through `writeClaudeCreds` — Anthropic rotates the refresh token on every call and the keychain MUST be updated, or downstream consumers (Claude Code, Claude Desktop) 401.
- `Sources/Usage/AppUsage.swift` — `plan` field carries Claude's `subscriptionType` (from keychain) or Codex's `plan_type` (from API top-level). Surfaced as the chip badge in `SettingsView` + `UsageView`.

## Build details

- `build.sh` — universal binary (arm64 + x86_64 via `lipo`), macOS 13+, ad-hoc codesign, embeds Sparkle.framework with `@executable_path/../Frameworks` rpath.
- Unsigned by Apple — no $99 Developer ID. The ad-hoc sign is just to dodge "is damaged and can't be opened" Gatekeeper rejection on download. Sparkle's EdDSA signing handles update integrity independently.
- `scripts/setup-sparkle.sh` downloads Sparkle 2.9.1 into `Vendor/Sparkle/` (idempotent). Runs automatically as part of `build.sh`.

## What NOT to change without explicit user request

- The `5m / 15m / 30m` polling presets (`Sources/Model/RefreshIntervalStore.swift`) — Anthropic rate-limits aggressively. Anything below 5m burns the daily quota.
- The `claude-code/X.Y.Z` User-Agent string — Anthropic gates `/api/oauth/usage` on it. Without it, requests 401 even with a valid token.
- The bundle ID `dev.codexisland.CodexIsland` — changing it orphans every existing user's preferences and Launch-at-Login registration.
- The `SU_PUBLIC_KEY` constant in `build.sh`. See hard rule #2.

## Style

- Conventional Commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`. No `Co-Authored-By` lines.
- Strict TypeScript / Swift — no `any`, no force-unwraps without justification.
- Default to no comments. Only add when the WHY is non-obvious (a constraint, a workaround for a specific bug, behavior that would surprise a reader).
- Match existing style in the file you're editing, even if you'd do it differently.
