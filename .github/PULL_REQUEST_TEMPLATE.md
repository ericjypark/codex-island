## Summary

<!-- What problem does this solve, and what changes for the user? Link related issues; use Closes #123 only when this PR fully resolves one. -->

## Verification

<!-- List the checks you ran and their results. For behavior changes, give reproducible steps and expected results. State anything you could not verify. Metadata-only changes can use targeted validation. -->

- Checks and results:
- Steps to verify:
- Not verified:

## Screenshots (required for UI changes)

**UI changes must include screenshots of the changed UI.** Include before/after screenshots when modifying existing UI. For interaction or animation changes, also attach a short recording or GIF.

<!-- Remove this section only if the PR does not change UI. -->

## Risks

<!-- What could break? Include compatibility, migration, credentials, concurrency, display placement, or provider errors when affected. Otherwise write None. -->

## Checklist

- [ ] I read `CLAUDE.md` and the applicable `AGENTS.md` guidance.
- [ ] I included verification results and any remaining limitations.
- [ ] For UI changes, I attached the required screenshots (otherwise N/A).
- [ ] I removed credentials and private data from code, logs, and screenshots.

<!-- Codex review is configured separately in Codex settings and follows AGENTS.md. A review does not replace CI or maintainer approval. -->

### Release changes only

<!-- Remove this section unless the PR changes release behavior. A PR or ordinary CI run does not publish a release; pushing a v* tag does. -->

- [ ] `VERSION` stays monotonic semver and the bundle identity and Sparkle signing key stay compatible.
- [ ] I did not hand-edit appcast XML or Homebrew version/SHA values; release CI owns them.
- [ ] If this is a release version bump, the landing site's `VERSION` is kept in sync.
