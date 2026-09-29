# Windows local usage history

Live mode now reads local session usage, retains it in a Windows-owned SQLite ledger, and supplies the
Cost page, model breakdowns, Overview calendar, and usage-card studio. This is independent of quota
authentication. A missing quota login does not erase recorded usage, and hiding a provider does not
stop its history scan. The first launch opens the labeled demo; the account action in Providers switches
to live data and remembers that choice for the desktop shortcut.

## Sources and identities

The readers follow the corresponding Mac source contracts. They do not copy Mac logs or credentials.
An explicit history import can merge a Mac ledger containing usage metadata and counts.

| Source | Windows paths | Accounting and identity |
| --- | --- | --- |
| Codex | `$CODEX_HOME/sessions`, otherwise `%USERPROFILE%/.codex/sessions`; recursive `rollout-*.jsonl` | Each `last_token_usage` delta, with cached input removed from ordinary input. Cumulative session totals are excluded. Basename, timestamp, and occurrence identify a record. |
| Claude | Each comma-separated `$CLAUDE_CONFIG_DIR/projects`; otherwise `%USERPROFILE%/.claude/projects` and `.config/claude/projects` | Assistant usage, excluding synthetic messages. Message/request IDs deduplicate streaming updates. A later row replaces an earlier row only when all its components dominate; components from different rows are never combined. |
| Grok | `$GROK_HOME/sessions`, otherwise `%USERPROFILE%/.grok/sessions`; recursive `updates.jsonl` | Completed prompt/model totals, excluding incomplete or partial-cost updates. Prompt/model IDs prevent repeated final updates from adding usage twice. |
| Antigravity CLI | `%USERPROFILE%/.gemini/antigravity-cli/conversations/*.db` | Generation metadata joined to step timestamps. Stable generation usage IDs deduplicate multi-step usage and copied conversations. |
| OpenCode | `$XDG_DATA_HOME/opencode`, otherwise `%USERPROFILE%/.local/share/opencode` | SQLite messages plus legacy `storage/message` JSON. OpenAI and Anthropic usage is attributed to Codex and Claude. Persistent fingerprints deduplicate database, legacy, and fork copies. |

JSONL reads are streamed in 64 KiB chunks, with a 1 MiB record limit for Codex/Claude and 2 MiB for Grok.
An oversized or malformed record does not prevent later complete records from being read. Unchanged
JSONL files reuse an in-memory size/mtime parse cache. Scans skip directory junctions and symbolic links.
Database sources open read-only snapshots. Source files and credential stores are never rewritten.

Counts must be nonnegative, bounded integers, with positive total usage and a valid nonfuture timestamp.
Missing history evidence remains unavailable. Once records establish history, an empty current day can
correctly show zero. Unknown models retain their token counts and an explicit unpriced-usage notice.
The Codex reader retains the Mac reader's `gpt-5.4` fallback when a log has no model context; this is an
estimate, not proof that the session used that model.

## Persistence and refresh

`%LOCALAPPDATA%/CodexIslandPrototype/usage-history.sqlite3` uses Windows' native SQLite engine, WAL,
full synchronous transactions, and parameterized statements. The ledger stores usage metadata and
counts, not prompts, completions, or credentials. Hashed event identities and persistent aliases keep
repeated scans idempotent. Windows timestamps use integer milliseconds. The importer detects the Mac
schema's timestamps in seconds and converts them, retaining event identities and aliases. Identity
hashes use UTF-8 byte lengths on both platforms.

A current scan can correct an existing event, including reducing an earlier count. A late scan can add
new records but cannot overwrite a newer correction. Empty, deleted, truncated, and temporarily
unreadable source files do not delete retained events. Reads merge the latest committed database state
before applying a batch, so a stale in-memory view cannot overwrite another writer's newer correction.

If persistence fails, already observed and current records remain available in memory with a visible
warning. A later successful save commits those unsaved records. Corrupt files and newer schemas are
preserved rather than replaced. Unsaved records cannot survive process exit, and a corrupt database is
not claimed to be recovered.

All five sources scan on worker threads and publish independently. History aggregation, including
recalculation after a price update, also runs off the UI thread. Automatic refresh uses the existing
5/15/30-minute presets; simultaneous refreshes join one active batch. The footer and card studio can
request a manual scan. Healthy scans clear stale local-record warnings. The current implementation
rescans changed files in full and re-aggregates retained events; very large archives still need measured
performance coverage.

## Import and backup

In live mode, **Settings > General > History backup** offers **Import** and **Back up**. Import accepts
Mac or Windows schema-1 SQLite ledgers. It validates records, aliases, daily totals, dates, provider
ownership, and nonoverlapping recovery intervals before committing. Existing events and corrected
counts are preserved. Duplicate identities and aliases are skipped. A snapshot of existing Windows
history is saved beside the ledger before an import; invalid merges roll back atomically.

Backups use SQLite's snapshot API, include committed WAL content, and produce a portable database.
A chosen export is replaced only after its new snapshot finishes. The active database cannot be used
as its own export destination. Imports wait for an active scan and publish newly aggregated history
before reporting completion. The actions are disabled in demo mode.

Recovered daily totals retain their source date and timezone interval, including 23- and 25-hour DST
days. Only the portion missing from observed events is added. Recovered usage has no inferred model,
timestamp within the day, or API price. It remains explicitly unpriced in value cards and captions.
An unpriced token is not treated as an unreadable-file error in the footer.

`--data-dir` selects a separate absolute folder for preferences, history, pricing, currency cache, and
the current-state diagnostic. Restarts preserve that selection. This supports an isolated history
preview while Windows CLI credentials continue to belong to their own CLIs.

## Prices, dates, and exports

The app includes the Mac source's 33 fallback model rates and reads the same
[public model catalog](https://ericjypark.github.io/codex-island-model-catalog/v1/models.json).
Validated prices are cached for 24 hours with conditional requests; automatic failed attempts are
spaced by six hours. An incomplete or malformed catalog cannot erase the previous table. Catalog
entries override matching seed rates, while omitted models retain their fallback. The Mac's historical
Gemini introductory-rate boundary is applied using each event's timestamp.

Amounts are API-rate estimates in USD before display currency conversion. They are not subscription
charges or actual bills. Input, output, cache creation, and cache reads have separate rates. Unpriced
tokens stay in totals, add a `+` to partial dollar values, and are identified in card captions. The API
value card cannot export an entirely unpriced period as a zero-dollar result.

Today, month, calendar days, and rolling card periods use local calendar dates. Model breakdowns use
rolling five-hour and seven-day windows; their token metric counts input plus output. Overview and
cards include cache tokens. The calendar combines all four providers regardless of the two header
selections. Cards refresh when history changes and when the local date changes, without recreating
the signature field during background updates.

## Verification and remaining work

The 48 history checks in `tests/logic/HistoryTests.cs` use temporary synthetic logs and databases. They
cover all five readers, duplicate and corrected records, missing logs, corrupt/newer ledgers, failed-save
recovery, source immutability, malformed data, price caching, DST, partial pricing, and stale warnings.
The complete logic suite passes 232 checks, including the seven swipe-input regressions.

`tests/run-live-render.ps1` passes 50 checks through the actual WPF surface. It renders synthetic records
through the real readers, ledger, summary, calendar, model rows, and card exporter. Exact totals persist
after deleting the temporary source logs and reopening the history service. These are integration
checks with controlled data, not an actual provider-account session.

An additional Mac-ledger comparison passes 1,774 checks on Windows 11 ARM at 200% display scaling.
The source snapshot is created through a read-only SQLite connection, with checksums verified after
copying it into the guest. `reference/history.sh` compiles the actual Mac cost sources and exports the
reference with a fixed clock, timezone, and price table. The Windows test uses the production importer,
history coordinator, summaries, calendar, and card renderer. Every positive daily bucket, Today/Month
total and cumulative point, model row and share, and all five card periods match the Mac result.
Date-range punctuation uses the Windows interface's hyphen convention. Reimport, portable backup,
restore, restart without source files, Unicode identities, overlap rejection, and scan/import ordering
are covered. Native captures include all four cost styles, model layouts, calendar selection, and cards.
Generated ledgers, personal totals, captures, timing samples, and reports stay in ignored artifacts.
The running app also passed the native Save/Open dialog flow: a saved backup reimported with zero new
events or recovered days, while the calendar retained its exact total. These controls were exercised
in the separate interactive profile, with the original preferences preserved.

Run `tests/run-mac-history.ps1 -Snapshot <snapshot-folder>` for the comparison. After it passes,
`tests/open-mac-history-preview.ps1 -Snapshot <snapshot-folder>` builds a separate interactive app
profile and creates a **CodexIsland Mac history** desktop shortcut. The ordinary profile remains separate.

Remaining work includes real Windows session-archive validation, desktop-app and WSL discovery,
recovery directly from Claude daily-statistics files, larger-archive performance, wake/network behavior,
quota-history curves, reset credits, and remaining provider-account validation. Codex and Antigravity
live quota requests are covered separately in [LIVE-PROVIDERS.md](LIVE-PROVIDERS.md). The broader motion,
visual, device, packaging, and update requirements remain in [PARITY.md](PARITY.md).
