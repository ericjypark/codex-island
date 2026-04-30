# CLAUDE.md

Project-specific guardrails. **Read every section before touching this repo.**

## Release process — MANDATORY

This app ships via Sparkle auto-update. **Skipping any step below breaks updates for every existing install.** No exceptions.

### The loop

```sh
# 1. Make changes, commit normally to main
git commit -am "feat: ..."

# 2. Bump VERSION
echo "0.0.X" > VERSION
git commit -am "chore(release): bump VERSION to 0.0.X"

# 3. Tag + push — fires the release workflow
git tag v0.0.X
git push origin main v0.0.X

# 4. Wait for CI (~1.5 min). It builds the universal DMG, signs it with the
#    EdDSA key from the SPARKLE_ED_PRIVATE_KEY secret, generates appcast.xml,
#    uploads both as release assets, AND mirrors the cask to
#    ericjypark/homebrew-tap with the freshly-built version + SHA.
gh run watch --exit-status

# That's it. No follow-up cask bump needed — CI handles it.
```

### Hard rules

1. **Don't manually edit `Casks/codexisland.rb` for a version bump.** CI rewrites it on the homebrew-tap side at release time. Manual edits to either copy will be overwritten or drift. (You CAN edit unrelated cask metadata — postflight, zap, livecheck — via a normal commit; CI preserves those.)
2. **Never edit `docs/appcast.xml` by hand.** It's a release asset built by `release.sh` from the signed DMG. Hand-edited entries fail Sparkle's EdDSA check.
3. **Never commit anything from `Vendor/Sparkle/`.** It's gitignored. The `public-ed-key.txt` lives there too — it must be readable by `build.sh` but never tracked.
4. **Never rotate the Sparkle keypair without a migration.** If you generate a new keypair, every existing install will reject every future update because the embedded `SUPublicEDKey` no longer matches. The migration path is: ship one final build with the OLD key that also embeds the new one, wait for users to upgrade, then switch. In practice: don't rotate.
5. **Never push to `main` without `git pull --rebase` first when working from a fresh clone.** History was rewritten 2026-04-30; old clones are stale.

### CI secrets (one-time setup)

The release workflow needs two GitHub Actions secrets on this repo:

- **`SPARKLE_ED_PRIVATE_KEY`** — the EdDSA private key (export with `Vendor/Sparkle/bin/generate_keys -x <file>`, paste the file contents). Without it the appcast can't be signed.
- **`HOMEBREW_TAP_TOKEN`** — fine-grained PAT with `contents: write` on `ericjypark/homebrew-tap` only. Without it CI emits a warning and the tap goes stale, but the GitHub Release still ships fine.

### Local dry-run

`./release.sh` from your machine produces a signed DMG + appcast in `dist/` using the Keychain key (the private half lives in macOS Keychain under service `https://sparkle-project.org`). Use this to sanity-check the Sparkle prompt against a fake `SUFeedURL` before tagging.

To build with auto-update disabled (e.g. a debug copy): `SU_FEED_URL= ./build.sh`.

### Why not bundle the cask bump?

The release workflow rebuilds the DMG on a CI runner, so the SHA-256 isn't predictable from local builds (different Xcode SDK, code-sign timing, etc.). The cask must point at the SHA of the DMG that's actually attached to the GitHub Release, which only exists after CI completes.

## Architecture pointers

- `Sources/Window/IslandWindowController.swift` — anchors the borderless overlay window over the notch. Listens to `NSApplication.didChangeScreenParametersNotification` to reposition on display changes; prefers the screen with `safeAreaInsets.top > 0`.
- `Sources/Update/UpdaterController.swift` — wraps Sparkle's `SPUStandardUpdaterController`. Reads `SUFeedURL` / `SUPublicEDKey` from Info.plist (injected by `build.sh`). Auto-check cadence is stored by Sparkle itself in `NSUserDefaults` under `SU*` keys.
- `Sources/Usage/UsageFetcher.swift` — Codex (`/wham/usage`) and Claude (`/api/oauth/usage`) fetchers. Claude requires `claude-code/X.Y.Z` User-Agent + `oauth-2025-04-20` beta header. Refresh-token rotation is wired through `writeClaudeCreds` — Anthropic rotates on every refresh and the keychain MUST be updated or downstream consumers (Claude Code, Claude Desktop) 401.
- `Sources/Usage/AppUsage.swift` — `plan` field carries Claude's `subscriptionType` (from keychain) or Codex's `plan_type` (from API top-level). Surfaced as the chip badge in `SettingsView` + `UsageView`.

## Build details

- `build.sh` — universal binary (arm64 + x86_64 via `lipo`), macOS 13+, ad-hoc codesign, embeds Sparkle.framework with `@executable_path/../Frameworks` rpath.
- Unsigned by Apple — no $99 Developer ID. The ad-hoc sign is just to dodge "is damaged and can't be opened" Gatekeeper rejection on download.
- `scripts/setup-sparkle.sh` downloads Sparkle 2.9.1 into `Vendor/Sparkle/` (idempotent). Runs automatically as part of `build.sh`.

## What NOT to change without explicit user request

- The `5m / 15m / 30m` polling presets (`Sources/Model/RefreshIntervalStore.swift`) — Anthropic rate-limits aggressively. Anything below 5m burns the daily quota.
- The `claude-code/X.Y.Z` User-Agent string — Anthropic gates `/api/oauth/usage` on it. Without it, requests 401 even with a valid token.
- The Sparkle public key in `Vendor/Sparkle/public-ed-key.txt`. See rule 5 above.
- The bundle ID `dev.codexisland.CodexIsland` — changing it orphans every existing user's preferences and Launch-at-Login registration.

## Style

- Conventional Commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`. No `Co-Authored-By` lines.
- Strict TypeScript / Swift — no `any`, no force-unwraps without justification.
- Default to no comments. Only add when the WHY is non-obvious (a constraint, a workaround for a specific bug, behavior that would surprise a reader).
- Match existing style in the file you're editing, even if you'd do it differently.
