# Contributing to CodexIsland

Thanks for being here. CodexIsland is small enough that any contribution moves the project meaningfully — bug reports especially. Here's how to keep things smooth.

## Reporting bugs

Use the [issue chooser](https://github.com/ericjypark/codex-island/issues/new/choose)
for bug reports, feature requests, or provider API regressions. Other questions
can use a blank issue. Bug reports ask for the app version shown in Settings,
OS and hardware, installation method, observed and expected behavior, and
reproduction steps. For source builds, include the commit and say which app
copy you launched.

Logs and API responses are optional. Share only the relevant, redacted evidence;
never post bearer tokens, cookies, credential files, or Keychain contents.
CodexIsland reads Claude credentials but does not refresh OAuth tokens or write
credentials. Claude Code owns that process.

## Building locally

```sh
./build.sh
open build/CodexIsland.app
```

`./scripts/verify.sh` builds and smoke-launches the binary for one second — useful in pre-commit hooks since the app runs forever and a normal `./build.sh && ./build/.../CodexIsland` would block.

No Xcode project, no SwiftPM. Just `swiftc Sources/**/*.swift`.

## Pull request checks and reviews

Every pull request runs the Swift regression suite, builds and smoke-launches
the universal macOS app, and validates the GitHub Actions workflows. These checks run again after
new commits and also run on `main`. Forks use the same checks without repository
secrets. Run `bash scripts/run-tests.sh` and `./scripts/verify.sh` locally before opening
a PR; workflow edits can be checked with `actionlint`.

The PR template asks for the problem, verification results, UI evidence when
applicable, and risks. Record unavailable checks rather than marking them as
passed. Metadata-only changes can use targeted validation.

Codex reviews use the official GitHub integration and follow the
`Code Review Rules` in `AGENTS.md`: provider/account routing, quota and credit
semantics, CLI-owned credentials, durable usage history, truthful cost estimates,
native panel behavior, privacy, and Sparkle compatibility. This repository is
configured to review all PRs after each push. Automatic reviews are configured in
[Codex settings](https://chatgpt.com/codex/cloud/settings/code-review), separately
from these templates and the CI workflow. For another repository, enable code
review, choose whose PRs receive automatic reviews, and set the review trigger.
Check personal automatic-review preferences when using that mode. See the
[official setup guide](https://learn.chatgpt.com/docs/third-party/github).

For another review, comment `@codex review` on the PR. An existing PR may have
no review or only a review of an older commit; configuration alone is not proof
that its current head was reviewed. Check the reviewed commit against the latest
head, resolve valid findings, and wait for CI on the latest commit before merging. Reviews do not merge or release changes. A review
service being unavailable does not establish whether the app builds or passes
tests; maintainer approval is still required.

## Code style

- **Lowercase Conventional Commits.** `feat(scope): summary`, `fix(scope): summary`, `chore: summary`. Body explains the *why*, not the *what*. The diff is the what. See git log for examples.
- **Atomic commits.** One logical change per commit; each commit must build and run via `./scripts/verify.sh`.
- **No AI vocabulary** — words like *comprehensive*, *delve*, *crucial*, *robust*, *seamless* are banned in commit messages, code comments, and docs. Direct words are better.
- **No `Co-Authored-By` lines** — including Claude / Copilot / etc. tags. Keep authorship clean.
- **Comments only when the WHY is non-obvious.** A hidden constraint, a workaround for a specific bug, behavior that would surprise a reader. If removing the comment wouldn't confuse the next person, don't write it.
- **Match existing style.** This codebase favors small files, named extensions on `Animation` / `Color`, and explicit `@MainActor` where AppKit insists.

## Things that need work

- Multi-monitor support. Right now the app chooses one target screen: the first notched display, otherwise `NSScreen.main`. Users with multiple notched displays should ideally see one panel per screen (or at least an option).
- Real history for the SparkChart. The synthesized noise is honestly decorative. If either Anthropic or OpenAI exposes a usage time-series, we should switch.
- Accessibility. VoiceOver labels exist, but a high-contrast variant and a full keyboard/focus pass still need work.
- Sponsor an Apple Developer ID via [GitHub Sponsors](https://github.com/sponsors/ericjypark) and we'll ship a signed build.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Short version: be kind.
