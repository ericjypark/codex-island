# Provider connections

Settings → Providers selects one or two distinct providers. A single provider
occupies the left slot. Picking the provider already in the other slot swaps
them; the central swap button does the same. Existing Claude/Codex visibility
preferences migrate automatically, and order persists across launches.

All providers use the same Ring, Bar, Stepped, Numeric, and Sparkline views,
used/remaining preference, peek pills, and threshold alerts. A provider's data
selects the metrics; changing providers does not change the chart style.

## Codex limit windows

Codex charts follow the windows reported by the usage API, not the plan name.
A weekly-only response displays one compact chart centered in the provider column.
Two reported windows retain the 5h/week pair. The discovered window list survives
failed refreshes, so an offline request cannot bring back a removed 5h tile.
Zero-percent windows remain visible. Peek and alerts select the same available
window, and chart styles and history keys remain unchanged.

## Grok subscriptions

Sign in with the official Grok CLI (`grok login`) using your Grok subscription.
A grok.com browser login alone does not create the CLI session this integration
reads. Settings opens the CLI login when installed, or the official Grok Build
page when it is missing. After signing in, choose Refresh connection.

The adapter reads `$GROK_HOME/auth.json` (default `~/.grok/auth.json`) and requests
credit usage from the Grok CLI billing service. On expiry or HTTP 401, the app
runs `grok models` once to let the CLI
renew its session, then rereads credentials and retries. It never rotates or writes
the CLI's tokens itself. The credits response supplies the subscription percentage
and weekly or monthly period label. Unified billing accounts, or responses without
a usable percentage, also query the default billing endpoint for `used / monthlyLimit`.
On-demand spending is never substituted for included subscription quota. Missing
percentages remain unknown; a billing period alone is not interpreted as zero usage.

When a connected provider reports no readings, its column shows an actionable
empty state instead of an empty chart and reset timer. A successfully fetched
Free plan shows “No active subscription”; paid or unknown plans show “Usage
unavailable.” Both link to provider settings. Actual readings, including 0%,
remain visible regardless of the plan label. The Cost page reuses the same
subscription state when both cost windows are unavailable and contain no usage;
existing cost records remain visible.

## Google Antigravity

Sign in with the official `agy` CLI. The desktop app is not required and does
not need to be running. Settings opens `agy` in Terminal when installed, or the
official CLI installation page when missing. After signing in, choose Refresh
connection.

The adapter reads the CLI's macOS Keychain entry (`gemini` / `antigravity`) without
writing it. On expiry or HTTP 401, the app runs `agy models` once,
then rereads the Keychain and retries. The CLI owns token refresh and persistence.
These model-list commands run without a prompt, with closed stdin and a 25-second
timeout; they do not start an agent turn. Failed renewal is reported as a connection
error, and HTTP 403 is not treated as proof of logout. It resolves the signed-in account's project via
`loadCodeAssist`, then passes that project to `retrieveUserQuotaSummary`.
The account project isolates display preferences and quota history. A Gemini API
key alone is not treated as an Antigravity subscription login.

Gemini is the preferred default group when present; otherwise an available group
is selected deterministically. Reported five-hour and weekly windows take
precedence. Settings can select another model group, one or two metrics, their
order, and which displayed metric drives peek and alerts. Use defaults restores
the automatic selection. No five-hour window is invented for a weekly-only plan.

Preferences use account identity when supplied by the provider. Quota history
is stored under hashed account and metric identifiers; an unidentified session
does not write persistent quota history. A removed custom group stays unavailable
until the user selects another group or restores defaults.

## Limits

Subscription limits and local cost history are separate sources. Cost, Tokens,
Value, Trend, model breakdowns, and the activity grid use the same aggregation
and views for every provider. Local history covers records on this Mac, across
local CLI accounts; it is not an account-wide billing statement.

Antigravity reads `~/.gemini/antigravity-cli/conversations/*.db` using read-only
SQLite transactions, including committed WAL data while the CLI is running.
`gen_metadata` stores one protobuf `CortexStepGeneratorMetadata` per model call.
The reader takes usage and response model from `chat_model`, and joins its
`step_indices` to `steps.metadata.created_at`. Input and cache buckets are
already disjoint; output already includes thinking. Provider message IDs dedupe
copied/forked calls. Transcript files and their chunk copies are not summed.
No desktop process, status-line hook, or credential refresh is needed.

Grok reads timestamped prompt usage from persisted ACP `updates.jsonl` under
`$GROK_HOME/sessions` (default `~/.grok/sessions`). It normalizes full-input ACP
counts into uncached/cache buckets and deduplicates repeated prompt/model IDs.
Incomplete usage and records without timestamps or per-model counts are omitted
with a local-records notice. This path has fixture coverage; a real Grok session
with persisted usage is still needed to validate the installed CLI's format.

An absent record is shown as unknown, rather than zero spend. Unreadable or
incomplete histories surface a local-records notice instead of a green Synced
status. Unknown model prices retain token/activity data and show an unpriced
warning. Local summaries do not depend on quota login succeeding.

Dollar values estimate API-equivalent token cost, not subscription charges.
Gemini 3.6/3.7/3.8 Flash use the published standard token/cache rates, including
the 2027 introductory-price cutoff applied at the call timestamp. This excludes
cache storage, search/tool charges, and discounts. See [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).
The Value view uses the [US monthly AI Pro reference price](https://one.google.com/about/plans)
when that exact plan is detected; an unknown plan price is shown as unavailable.

Connections follow the existing 5/15/30-minute polling presets. A manual refresh
is available; Grok HTTP 429 responses enforce a 15-minute cooldown. Deselecting a
provider cancels its pending request, and swapping positions does not fetch.

Grok's CLI billing response and Antigravity's quota protocol can change.
Fixture tests cover parsing and selection; validating authentication requires a
signed-in CLI. Authenticated requests use HTTPS and do not follow redirects.

## Provider colors

Provider identity colors live in `Sources/Theme/Colors.swift` and are routed
through `IslandProvider.color` for marks, usage charts, cost charts, and peek.
These are CodexIsland display colors, not claims about official brand palettes.

| Provider | Color | Hex |
| --- | --- | --- |
| Claude | Terracotta | `#CC785C` |
| Codex | Sky blue | `#5AA8F0` |
| Grok | White | `#FFFFFF` |
| Antigravity | Lilac | `#B69CFF` |

Antigravity uses a separate hue from Codex so adjacent providers are recognizable
at a glance. Green, amber, and red remain reserved for status and alerts. Keep
provider names and distinct marks visible so identification never depends only
on color.

## Demo mode

`CODEXISLAND_DEMO=1` also supplies synthetic Grok and Antigravity cost totals,
cumulative trends, and overview token history. VALUE uses illustrative monthly
plan baselines ($30 and $19.99 respectively) only in demo mode. These fixtures
never write the real cost cache or establish live subscription prices.
