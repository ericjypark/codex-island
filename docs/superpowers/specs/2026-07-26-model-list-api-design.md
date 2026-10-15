# Remote Model List & Pricing — Design

**Date:** 2026-07-26
**Status:** Approved (brainstorm complete)

## Summary

Move the per-model price table out of the app binary and into a public,
bot-maintained JSON file served by GitHub. A CronJob on the maintainer's
k3s cluster polls LiteLLM, merges hand-maintained overrides, runs a sanity
gate, and commits the result. The app fetches it once a day and falls back
through a disk cache to an embedded seed, so costs never silently collapse
to $0.

New models stop requiring an app release.

## Problem

`Sources/Cost/Pricing.swift` embeds 32 models × 4 rates as a Swift
dictionary. Adding a model means editing that file, bumping `VERSION`,
tagging, and pushing a Sparkle release — and users see correct dollar
totals only after they take that update. Four of the eight commits that
have ever touched `Pricing.swift` were pure "add a model" changes.

Unknown models price to $0 (ccusage parity), so the failure is silent:
between a model's launch and the release that adds it, users see totals
that are simply wrong.

## Decisions made during brainstorm

- **Distribution channel is GitHub, not the maintainer's server.** The app
  already contacts `github.com` daily for the Sparkle appcast
  (`build.sh:35`), so serving pricing from GitHub adds *zero* new trust
  surface. Routing the app at a personally-operated host would add one, and
  would contradict README.md:84 ("no proxy service").
- **The data is public and auditable.** Prices live in a public repo where
  anyone can verify a value or send a PR. For an open-source cost tracker
  this is a feature, not a leak — it is the opposite of a private
  black box quoting numbers users cannot check.
- **The Raspberry Pi produces data; it never serves users.** The merge bot
  runs on the Pi's k3s cluster and pushes to GitHub. If the Pi is down,
  nothing user-facing degrades — the file keeps being served, it just stops
  getting fresher.
- **Hybrid data source.** LiteLLM auto-sync plus a hand-maintained
  `overrides.json`. Pure auto-sync cannot reproduce the deliberate
  deviations already encoded in `Pricing.swift` (gpt-5.6 cache writes at
  1.25× input, Sonnet 5 introductory pricing, `gpt-5-pro` cache-read of 0),
  and LiteLLM has no entry at all for some ids the CLIs emit.
- **Three-tier fallback in the app.** remote → disk cache → embedded seed.
  A pod outage, an offline laptop, or a corrupt payload must never turn
  into $0 costs.
- **Payload carries `displayName`.** `prettyModelName()` is rule-based and
  already mis-renders ids that break the pattern (`gpt-5.6-sol` →
  `GPT-5.6-sol`). Serving the name kills that class of release too.
- **User counting is not built.** GitHub release DMG download counts
  already answer "how many people use this" — Sparkle downloads the DMG to
  update, so per-release counts track active installs (374–745 across
  recent releases). Adding a persistent identifier or a counted ping
  endpoint would be app telemetry, which README.md:277 promises does not
  exist. If finer numbers are ever needed, the honest path is explicit
  opt-out telemetry in its own release — not a side effect of this work.

## Architecture

```
LiteLLM ──┐
          ├─► [Pi k3s CronJob] ──commit──► public repo ──► GitHub Pages ──► app
overrides ┘    merge + sanity gate          (auditable)      (Fastly CDN)
   ▲                                                              │
   └── git is the source of truth for both input and output       ▼
                                              remote → disk cache → seed
```

## Payload

`https://ericjypark.github.io/codex-island-model-catalog/v1/models.json`

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-26T01:00:00Z",
  "source": "litellm@<sha> + overrides",
  "models": {
    "claude-opus-4-8": {
      "displayName": "Opus 4.8",
      "inputPerMillion": 5,
      "outputPerMillion": 25,
      "cacheCreationPerMillion": 6.25,
      "cacheReadPerMillion": 0.5
    }
  }
}
```

- Keys are **canonical** model ids — the date suffix is already stripped
  (`claude-haiku-4-5-20251001` → `claude-haiku-4-5`), matching what
  `Pricing.canonicalModel` produces before lookup.
- A map, not an array: decodes straight into `[String: Rates]`.
- `source` is informational; the app ignores it.
- The app **rejects any payload whose `schemaVersion` is not 1** and keeps
  its cache. A breaking change ships at `/v2/models.json`; old installs keep
  reading `/v1/` forever.

## Sync bot

Go binary, run as a k3s CronJob every 6 hours.

1. Clone the data repo (shallow).
2. `GET https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
3. **Select** entries where `mode` is `chat` or `responses`, the id contains
   no `/` (drops `azure/`, `bedrock/`, `vertex_ai/` re-listings), and the id
   matches a pattern in `config.json` (`claude-*`, `gpt-5*`, `o[0-9]*`).
4. **Map** to per-million rates (LiteLLM stores per-token):
   - `input_cost_per_token` × 1e6 → `inputPerMillion`
   - `output_cost_per_token` × 1e6 → `outputPerMillion`
   - `cache_creation_input_token_cost` × 1e6 → `cacheCreationPerMillion`,
     falling back to `inputPerMillion` when absent (OpenAI bills cache
     writes at the input rate)
   - `cache_read_input_token_cost` × 1e6 → `cacheReadPerMillion`,
     falling back to 0
5. **Canonicalize** ids and dedupe date-pinned variants onto the base id.
   If two variants disagree on a rate, keep the one from the newest date
   suffix and log the conflict.
6. **Apply `overrides.json`** per-model and per-field. An override wins
   unconditionally, including `displayName`.
7. **Generate `displayName`** for models without an override, using the same
   rules as `Pricing.prettyModelName`.
8. **Sanity gate** (see below).
9. If the `models` map differs from the committed `v1/models.json`, write it,
   commit, and push. Otherwise exit 0 without a commit.

`generatedAt` therefore advances only when prices actually change — a run
that confirms nothing changed produces no commit and no new timestamp. The
comparison deliberately ignores `generatedAt` itself; comparing the whole
file would make every run differ and commit 1,460 times a year.

### Sanity gate

The app release cycle used to be an implicit review gate on every price
change. This replaces it. Without it, one bad upstream commit reaches every
user within a day.

- **Run-level:** if the merged model count is below 50% of the currently
  published count, reject the entire run — no commit, non-zero exit so the
  CronJob surfaces as failed.
- **Model-level:** a rate that is negative, or **any** of the four rates above
  1000, is rejected for that model. The ceiling covers every field because the
  ratio rule below is skipped entirely for a model with no published baseline —
  so for a brand-new model this is the only bound that applies, and output
  tokens dominate the app's spend arithmetic.
- **Model-level:** a rate that moved by ≥10× from the published value is
  rejected for that model. The rule applies only when the published value
  is greater than zero — a rate legitimately moving off 0 (a model gaining
  prompt caching, say) has no meaningful ratio.
- A rejected model **keeps its previously published values** rather than
  disappearing. Dropping it would price it at $0, which is exactly the
  outcome this design exists to prevent. A brand-new model with no previous
  value is omitted instead — identical to today's unknown-model behavior.
- **Models are never removed by the bot.** If LiteLLM drops an entry, the
  published value stays. Removal requires an explicit override.

## Repository layout

`ericjypark/codex-island-model-catalog` — **must be switched from private
to public**; it is both the audit surface and the serving channel.

```
v1/models.json          generated — the only file the app reads
overrides.json          hand-maintained; beats LiteLLM
config.json             id patterns to select
.nojekyll               keep Pages from processing the tree
cmd/sync/               the Go bot
k8s/namespace.yaml
k8s/cronjob.yaml
k8s/secret.yaml         (template; real token applied out of band)
```

GitHub Pages: deploy from `main`, root folder.

## Kubernetes objects

Namespace `codexisland` on the Pi's k3s.

- **`CronJob model-list-sync`** — every 6h, `restartPolicy: OnFailure`,
  `backoffLimit: 2`, `concurrencyPolicy: Forbid`, image
  `ghcr.io/ericjypark/codex-island-model-catalog:<sha>` — named after the
  repo, matching the existing `ghcr.io/ericjypark/<name>:<sha>` convention
  on this cluster.
- **`Secret codexisland-git`** — a fine-grained PAT with `contents: write`
  scoped to this one repo.
- **`Namespace codexisland`**.

A CronJob rather than a Deployment: the work is periodic, so there is no
long-running process to keep alive. `OnFailure` retries a failed run, and
the next scheduled run recovers regardless of what happened to the last one.

No Service, no Ingress, no nginx vhost, no TLS certificate — nothing on the
Pi is reachable from outside, so the existing shared certbot certificate and
the hardcoded-ClusterIP nginx pattern are both left untouched.

## App changes

### `Sources/Cost/PricingCatalog.swift` (new)

Holds the resolved catalog and owns the fallback ladder.

- Disk cache at `~/Library/Caches/dev.codexisland.CodexIsland/model-prices.json`,
  matching the convention in `LogParseCache.cacheURL`. Stores the payload
  plus the last `ETag` and fetch timestamp. `Caches` is purgeable by macOS;
  losing it costs one refetch and drops to the seed in the meantime, which
  is exactly the intended behavior.
- On launch: load the cache synchronously; if absent or unreadable, the seed
  stands.
- Refresh on launch when the cached payload is older than 24h, and every 24h
  thereafter while running: `GET`
  with `If-None-Match`. 304 → keep the payload, update the timestamp only.
  200 → validate `schemaVersion`, decode, atomically swap, persist.
- Any failure — network error, non-2xx, malformed JSON, wrong
  `schemaVersion` — leaves the current state untouched. No user-visible
  error; staleness is already surfaced in Settings.

### `Sources/Cost/Pricing.swift`

- `table` → `seedTable`, unchanged in content. It becomes "last known good
  at build time" rather than the authority.
- `cost(for:)`, `isKnown(_:)`, and `prettyModelName(_:)` consult the live
  catalog first, then fall back to `seedTable` and the existing name rules.
- `snapshotDate` → `seedSnapshotDate`, still the build-time constant, now
  describing only the seed.

**Call sites do not change.** The build uses plain `swiftc` with no
`-swift-version 6` and no strict-concurrency flags (`build.sh:60`), so
`Pricing` keeps its synchronous `static` API. `CostSummary` and
`StatCardSummary` are untouched.

The stored catalog is guarded by an `os_unfair_lock`, and that is not
optional. `CostStore` runs `CostSummary.summarize` inside two concurrent
`Task.detached` blocks (`CostStore.swift:67`, `CostStore.swift:77`), so
`cost(for:)` is already read from background threads — installing a new
catalog from the refresh would otherwise be a live data race. An
uncontended lock costs tens of nanoseconds per event, which is noise next
to the JSONL parsing that produced those events.

### `Sources/Views/SettingsView.swift`

`costSubtitle()` keeps its "pricing data %dd old" strings and the 60-day
threshold. The number becomes **days since the last successful fetch**
(200 or 304), falling back to days since `seedSnapshotDate` when no fetch
has ever succeeded. No new localization keys.

It deliberately is *not* days since `generatedAt`. Because the bot commits
only on change, a long-stable price table would otherwise trigger a false
"90d old" warning while the app was in fact checking daily and finding
nothing new. "How long since I reached the source" is the signal that
actually indicates the user's numbers might be wrong.

### `README.md`

The Privacy section (README.md:273) currently implies the app talks only to
`chatgpt.com` and `api.anthropic.com`. Add the new destination: the app
fetches model pricing from GitHub. "No app telemetry" and "No app
analytics" both remain true and stay as-is.

## Testing

**Bot (Go, standard `go test`):**

- override precedence beats LiteLLM, per-field
- each sanity-gate rule: count collapse, negative rate, absurd rate, 10×
  jump — and that a rejected model retains its previous value
- a model dropped upstream survives in the output
- date-pinned variants canonicalize and dedupe
- no commit when the merge is byte-identical to what is published

**App (Swift, `scripts/run-tests.sh`, bare `swiftc` — no XCTest/SPM):**

- payload decodes into the catalog; `schemaVersion: 2` is rejected
- fallback order: remote beats cache beats seed
- corrupt JSON leaves an existing cache intact
- a 304 preserves the payload and advances the timestamp
- `cost(for:)` uses a remote rate over a differing seed rate

`Pricing.swift` appears in two existing test targets
(`stat-card-summary-tests`, `stat-card-render-tests`); both need
`PricingCatalog.swift` added to their source lists.

## Out of scope

- **Regenerating the app's seed at release time.** A stale seed only affects
  someone who installs while offline and never connects; the first
  successful fetch heals it. Not worth a codegen pipeline.
- **Request counting / user telemetry.** See the decision above.
- **Serving anything from the Pi.** No public endpoint, no new subdomain.
- **Context windows, provider taxonomy, alias maps.** The app does not use
  them; designing fields with no consumer is cost without benefit.

## Operational prerequisites

These are one-time, manual, and outside the code:

1. Switch `codex-island-model-catalog` from private to public.
2. Enable GitHub Pages on `main` / root.
3. Mint the fine-grained PAT and apply it as `codexisland-git` in the
   `codexisland` namespace.
