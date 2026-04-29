# v0.1.0 — Launch

CodexIsland turns the MacBook notch into a Dynamic-Island-style live activity for Claude Code and Codex API rate limits. Hover the notch, see both providers, all four rate-limit windows.

## Highlights

- Two providers (Claude, Codex), four windows (5h + 7d each).
- Five chart styles (Ring / Bar / Stepped / Numeric / Sparkline) — Cmd-click cycles, persisted across launches.
- Lives in the notch, no Dock icon, no menu.
- 5-min polling against both providers' usage endpoints.
- Local only. No telemetry, no analytics, no third-party calls.

## Install

```sh
brew install --cask --no-quarantine codexisland
```

Or grab the DMG from this release, drag to `/Applications`, then:

```sh
xattr -d com.apple.quarantine /Applications/CodexIsland.app
```

(Unsigned — see [the README](README.md) for why.)

---

## Launch checklist

- [ ] First `git tag v0.1.0 && git push --tags` triggers CI build
- [ ] DMG verified by downloading + opening on a clean Mac (test the dequarantine command works)
- [ ] Homebrew Cask PR opened against `homebrew/homebrew-cask` (use the formula in `Casks/codexisland.rb`, replace the sha256 with the actual release sha)
- [ ] README install section tested by a non-developer friend
- [ ] Screenshots and GIF freshly generated from the v0.1.0 build
- [ ] Product Hunt: schedule for Tuesday-Thursday 12:01 AM PT
- [ ] X / Threads thread queued with hero GIF
- [ ] Reddit threads drafted for r/macapps, r/MachineLearning, r/OpenAI, r/ClaudeAI

## Product Hunt tagline (under 60 chars)

> AI usage limits, living in your MacBook notch.

(56 chars.)

## X / Threads draft

```
shipped CodexIsland — your Claude Code + Codex rate limits, living in
your MacBook notch.

hover the notch, see all four 5h/weekly windows. cmd-click to cycle 5
chart styles. no Dock icon, no menu, just the notch.

free + open source: github.com/eric-jy-park/codexisland
```

## Reddit drafts

**r/macapps**

> **CodexIsland — turns your MacBook notch into a Dynamic-Island-style indicator for Claude Code and Codex rate limits**
>
> Both Claude Pro/Max and ChatGPT Plus have hidden 5h + weekly token windows. Most people learn they've hit one when they get blocked mid-task. CodexIsland sits in your notch and shows you where you stand — hover to expand, see both providers, both windows, both reset times.
>
> No Dock icon, no menu, ~80KB binary. Free and open source. Install: `brew install --cask --no-quarantine codexisland`.
>
> Source: https://github.com/eric-jy-park/codexisland

**r/ClaudeAI**

> **Built a notch indicator for Claude Code rate limits**
>
> Got tired of running `claude --usage` to check where I am in the 5h window. CodexIsland reads the same auth Claude Code uses (env var → keychain → refresh) and surfaces both the 5h and weekly utilization in your MacBook notch. Hover to see numbers, click to cycle chart styles.
>
> Free, open source, MIT licensed. Same trick works for Codex (chatgpt.com/backend-api/wham/usage). Endpoints are undocumented — will probably need touch-ups when Anthropic ships a real one. PRs welcome.
>
> Source: https://github.com/eric-jy-park/codexisland

**r/OpenAI**

> **Mac app: notch indicator for Codex CLI rate limits (and Claude)**
>
> If you live in the Codex CLI: this is a free macOS overlay that reads `~/.codex/auth.json` and shows your 5h + weekly utilization in the MacBook notch. Bonus: same panel does Claude Code at the same time. Cmd-click to cycle five chart styles.
>
> No telemetry, no Dock icon. MIT.
>
> Source: https://github.com/eric-jy-park/codexisland

---

**SHA-256:** `<filled in by CI>`

⚠️ Unsigned build — see the README for install details.
