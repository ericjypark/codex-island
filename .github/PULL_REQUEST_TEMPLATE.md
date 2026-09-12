<!--
Title: lowercase Conventional Commits — `feat(scope): summary`, `fix(scope): summary`, `chore: summary`.
No `Co-Authored-By` lines. No AI vocab (comprehensive, delve, crucial, robust, seamless).
-->

## What changed

<!-- One or two sentences. The diff is the "what" — focus on the "why". -->

## Why

<!-- The user-facing problem or constraint. Link the issue: `Closes #123`. -->

## How to verify

<!-- Concrete steps a reviewer can run. Without this, the PR can't be reviewed.
     Example:
     1. `./build.sh && open build/CodexIsland.app`
     2. Open Settings → toggle X
     3. Confirm the chip updates within 5s and shows the new label
-->

1.
2.
3.

## Screenshots / recording

<!-- REQUIRED for any UI change (window placement, settings panel, chip layout, colors).
     Drag a PNG or short .mov in. -->

## Risk + blast radius

<!-- What could this break? Where should the reviewer look hardest?
     Examples:
     - Touches notch detection — needs verification on a non-notched display.
     - Changes refresh polling — verify we still respect 5m floor (Anthropic rate limits).
     - Touches Sparkle wiring — see release checklist below. -->

## Release impact

- [ ] No version bump needed (code/doc change with no shipped behavior difference)
- [ ] Bumps `VERSION` (will trigger a Sparkle auto-update for every install on next CI run)
- [ ] Touches `build.sh`, `release.sh`, `scripts/setup-sparkle.sh`, or `.github/workflows/release.yml`

## Pre-flight checklist

- [ ] `./scripts/verify.sh` passes locally (builds + smoke-launches)
- [ ] Manually launched `./build/CodexIsland.app` and exercised the changed code path
- [ ] Commits follow lowercase Conventional Commits; no `Co-Authored-By` lines
- [ ] No banned vocab (comprehensive, delve, crucial, robust, seamless) in commits, comments, or docs
- [ ] No new comments added unless the *why* is non-obvious
- [ ] No files added under `Vendor/` (gitignored on purpose)
- [ ] Did **not** hand-edit `Casks/codexisland.rb` version/SHA, or any appcast XML

### Sparkle / release-only PRs (skip if N/A)

- [ ] `VERSION` is monotonic semver (e.g. `0.0.43`, never `1` or `100`)
- [ ] `SU_PUBLIC_KEY` in `build.sh` is **unchanged** (changing it bricks auto-update for every existing install — see CLAUDE.md hard rule #2)
- [ ] If bumping `VERSION`, also bumped it in [`ericjypark/codex-island-landing`](https://github.com/ericjypark/codex-island-landing) so the marketing site doesn't lag
