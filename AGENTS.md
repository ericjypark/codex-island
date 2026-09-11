# CodexIsland

Read [CLAUDE.md](CLAUDE.md) before editing this repository. It contains the
shared release, credential-handling, build, documentation, and style rules.

## Code Review Rules

- Report actionable P0-P2 bugs introduced by the PR, with the triggering scenario,
  impact, and a precise changed-line reference. Skip style nits and speculative
  refactors. Distinguish unavailable review services from failing app tests.
- Preserve Sparkle update compatibility: the signing key, monotonic semver,
  bundle identity, signed appcast generation, and CI-owned Homebrew sync must
  continue to work for existing installations. A normal version bump is not
  itself a defect.
- Claude credentials are owned by Claude Code. Flag app-side OAuth refresh
  calls or credential-store writes; never recommend adding them. Re-reading
  credentials and letting the CLI refresh its own credentials are allowed.
  Preserve the documented usage headers and minimum five-minute polling.
- Check display changes, notched-screen placement, idle and Low Power behavior,
  concurrency, and provider error states when affected. Keep missing quota
  readings distinct from a real zero, and API-equivalent value distinct from
  actual billing. Persistent usage history must survive missing source logs.
