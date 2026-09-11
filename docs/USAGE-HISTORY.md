# Local usage history

CodexIsland retains captured token counts in its own SQLite database at
`~/Library/Application Support/dev.codexisland.CodexIsland/usage-history.sqlite3`.
This is durable application data, separate from the disposable parser caches
and provider-owned session files. The app never expires saved usage or deletes
it when an original log disappears.

## Capture

The existing local refresh reads all currently available records from Claude
Code, locally mirrored Claude Cowork sessions, Codex, OpenCode, Grok, and
Antigravity. Parser caches still avoid re-reading unchanged Claude and Codex
files. Capture runs at launch and on the existing refresh schedule; it does
not add network requests or change quota polling intervals.

Each call keeps its provider, model, timestamp, disjoint input/output/cache
counts, and a hashed identity. Calls with stable provider IDs update the same
entry across scans. Codex and older Claude records use the session filename,
timestamp, and repeated-timestamp ordinal. OpenCode's existing duplicate-call
fingerprints are retained as aliases so a surviving fork does not recount an
already saved call. Claude streaming repeats use a real recorded row whose
counts dominate the earlier row, never a synthesized sum of multiple rows.

Writes use SQLite transactions, WAL, and full synchronization. Separate
writers cannot overwrite each other's history, and an older in-flight scan
cannot replace a newer observation. The database is owner-readable only.
Failed writes preserve the file and keep live totals visible with a saving
error; the app never silently resets an unreadable archive.

## Recovered daily totals

Historical daily snapshots can be imported separately from individual calls.
They retain their original date, UTC interval, offset, token totals, and
input-plus-output totals. They are not converted into fabricated messages or
assigned a guessed model.

For each original interval, the app subtracts overlapping detailed usage and
adds only a positive remainder. More complete detailed records therefore
replace the aggregate contribution without being counted twice. This is a
conservative lower bound when the two sources may cover different calls.
The remainder keeps the original calendar date; moving it between hourly or
current-timezone daily buckets would invent a distribution the source did not
record. Overlapping aggregate intervals are rejected transactionally.

Recovered counts with no model breakdown remain unpriced. Usage cards identify
recovered daily totals, and their API-value view marks the missing pricing as
partial. Cached zero days do not establish that no activity occurred.

## Recover your Claude usage

Open **Settings → General → Recover Claude usage…**. The app scans local
records and shows the current total, the total after recovery, and the
additional tokens it found. Nothing is saved during this preview.

If older daily snapshots need a timezone, choose the timezone in which they
were recorded and click **Scan again**. Leave it unspecified if you do not
know. Expand **Older backups** to add an extracted Claude projects folder or
an old CodexIsland preferences file. Changing any selection clears the old
preview, so you must scan again before importing.

Click **Import recovery** to save the reviewed records. The app backs up the
archive, imports the exact records from the preview, and refreshes the usage
card. Records that appear in source files after the preview are not silently
included. If the app has already captured the same usage, it is not counted
again. An open **All time** card also refreshes after recovery.

The optional terminal script uses the same recovery code. No Xcode, Python,
login, or downloads are required. Start with a preview:

```sh
bash /Applications/CodexIsland.app/Contents/Resources/recover-claude-usage.sh
```

The preview shows the saved message and daily counts it found, your current
Claude total, and how many tokens recovery would add. It leaves your saved
counts unchanged. To save the verified records, run it again with `--apply`:

```sh
bash /Applications/CodexIsland.app/Contents/Resources/recover-claude-usage.sh --apply
```

Refresh CodexIsland, then open **Overview → Share usage** and select **This
year** or **All time**. You can repeat recovery safely. Copied Claude messages
are deduplicated by message and request IDs, and overlapping daily snapshots
contribute only the part not covered by detailed records. Recovery leaves
already captured messages intact and never reduces saved daily totals.

The default scan follows the app's Claude configuration, including locally
mirrored Cowork logs in the default search. To include another surviving copy,
point `--projects` at its extracted projects folder. Repeat the option for
multiple backups; archives such as `.tar.gz` must be extracted first:

```sh
bash /Applications/CodexIsland.app/Contents/Resources/recover-claude-usage.sh \
  --projects "/Volumes/Backup/old-home/.claude/projects"
```

Old CodexIsland daily snapshots are also checked. They may survive after
Claude's original logs are gone, but they do not record a timezone name. Add
`--time-zone` with the timezone where those snapshots were collected, then
preview again. For example, use `Asia/Seoul` only for snapshots recorded there:

```sh
bash /Applications/CodexIsland.app/Contents/Resources/recover-claude-usage.sh \
  --time-zone Asia/Seoul
```

Use `--preferences "/path/to/dev.codexisland.CodexIsland.plist"` to also check
a preferences file from an old backup. Repeat the option for multiple files.
Supported snapshots are `MacIsland.costCache.v4` through `v7`. A snapshot whose
daily boundaries do not match the supplied timezone is skipped. Snapshots
that already contain recovered display aggregates are also skipped, so the
same recovery is not reinterpreted under a different timezone. Add `--apply`
to the reviewed command when ready to save it.

Before an import changes an existing archive, the script saves a consistent
SQLite backup, including any pending WAL data, under
`~/Library/Application Support/dev.codexisland.CodexIsland/Recovery Backups/`.
The script prints its exact path; Settings offers **Show backup in Finder**.
Each backup is a standalone database that can be opened read-only without
copying WAL or shared-memory sidecars. These backups and the archive are
private to your user account. Original logs and preferences are never edited.
The terminal command does not start the app's UI, quota requests, or updater.

Each recovery commits its messages and daily snapshots in one transaction.
A storage failure rolls back the entire import. The added-token count is
measured inside that same transaction, so ordinary app captures happening
during recovery are not reported as recovered tokens.

Recovery cannot reconstruct deleted counters with no surviving source.
Undated session summaries, quota percentages, monthly totals without daily
records, conflicting daily counters, and messages without both usage IDs are
not imported. The ordinary app capture still supports older messages without
IDs; the recovery command requires IDs so copied backups cannot inflate totals.
Recovered daily totals include cache tokens but do not invent model prices.

From a source checkout, run `bash scripts/recover-claude-usage.sh`. It uses the
local build when available, then checks the standard Applications folders.
For another app location, set `CODEXISLAND_APP` to its `.app` path. The installed
app must include this recovery command; the script will not launch an older
app that lacks it. Run `--help` for all options.

## Limits

The database protects counts after capture. CodexIsland must be running while
provider records are still available to capture them; records already deleted
beforehand require another surviving source. Cloud-only activity or usage on
another computer is not automatically included. The database itself still
needs the user's normal device backup. It contains no prompts, responses,
tool payloads, or credentials, and it is not uploaded anywhere.

Run `bash scripts/test-usage-ledger.sh` to verify persistence across source
deletion, reopening, repeated scans, corrections, concurrent writers, storage
errors, and recovered aggregate overlap.
Run `bash scripts/test-claude-recovery.sh` for preview isolation, copied backup
deduplication, source preservation, repeat imports, archive backups, and
historical timezone checks. It also checks whole-import rollback, frozen
previews, concurrent capture attribution, excessive counters, unsupported
archives, and the Settings loading/preview/import states.
