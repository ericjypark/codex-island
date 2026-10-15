# Provider connections

Settings → Providers selects one or two distinct providers. A single provider
occupies the left slot. Picking the provider already in the other slot swaps
them; the central swap button does the same. Existing Claude/Codex visibility
preferences migrate automatically, and order persists across launches.

All providers use the same Rails, Ring, Grid, History, and Stepped views,
used/remaining preference, peek pills, and threshold alerts. A provider's data
selects the metrics; changing providers does not change the chart style.

## Codex limit windows

Codex charts follow the windows reported by the usage API, not the plan name.
A weekly-only response displays one quota in the provider column; Rails and History span its width, while Ring uses one empty-center gauge with an adjacent reading.
Two reported windows retain the 5h/week pair. The discovered window list survives
failed refreshes, so an offline request cannot bring back a removed 5h tile.
Zero-percent windows remain visible. Peek and alerts select the same available
window, and chart styles and history keys remain unchanged.

## Claude Enterprise credits

Enterprise accounts can report monthly `extra_usage` credits alongside or instead
of the five-hour and weekly windows. The app converts cent amounts to currency
units, keeps missing spend distinct from zero, and shows unlimited credit usage as an
amount rather than a quota percentage. Credit amounts use the API currency.
They describe credits consumed, not an invoice or an actual billed charge.

A missing `monthly_limit` is unknown; only an explicit `null` represents
unlimited credits. Incomplete credit readings are omitted.

Monthly credit limits are evaluated independently for threshold alerts. Reset
countdowns use only provider-supplied boundaries. Percentage-only history remains
available to charts but is not used to seed monthly spend after relaunch. A failed
refresh preserves a previous credit reading with the error shown beside it.

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

## Muse Code

Select Muse Code in either provider slot and sign in with the official `muse`
CLI. Settings opens Muse Code, or its official install page when the CLI is
missing. Run `/login` in Muse Code to change or restore the login, then refresh
the connection in CodexIsland.

The adapter reads the CLI's `providers.meta.access_token` from
`$MUSE_AUTH_PATH`, or `$XDG_CONFIG_HOME/muse/auth.json` (default
`~/.config/muse/auth.json`). An inline token takes precedence over Keychain.
Otherwise it reads the exact macOS Keychain item `ai.meta.dev.credentials` /
`meta`. macOS may request access to this CLI-owned item. Reads run off the main
thread and the Keychain helper is bounded to three seconds. CodexIsland never
writes the CLI credential store or refreshes its OAuth tokens.

Only the browser/device login's `dca:` credential can query subscription quota.
Dashboard and inference API keys are not subscription credentials. The adapter
sends an empty JSON POST to `https://api.meta.ai/muse-code/key` with
`x-api-version: 1.0.0`. This is the CLI's key-mint endpoint, not a documented
read-only usage API. Its response can include an inference key and payment
metadata; both are discarded. No model inference request is made. HTTPS
redirects are rejected. Automatic polling follows the existing 5/15/30-minute
presets and HTTP 429 enforces a 15-minute cooldown.

Reported `subs_usage.window` and `subs_usage.weekly` percentages and reset times
feed the existing charts, used/remaining toggle, metric selection, peek, and
alerts. Session and weekly alerts keep separate crossing memory. Without reset
metadata, alerts rearm only after an observed reading falls below the threshold;
missing readings cannot rearm them. The session label uses its reported duration. Over-quota percentages
fill the gauge; missing percentages never become zero. An inactive subscription
and incomplete billing have separate explanatory messages. Active subscriptions
can omit quota from the response, including while idle; CodexIsland shows usage
unavailable rather than inferring zero or reading browser cookies.

Account email scopes preferences and persistent quota history. Without an
account identity, no quota history is persisted. The credential is re-read
before accepting a response, so a changed login discards that result. A failed
request retains the last reading only for the same credential, marks it stale,
and excludes it from peek and alerts. A missing login clears the displayed quota.
Local token history and API-equivalent cost are not supported for Muse Code yet;
those views show unavailable rather than a fabricated zero or subscription bill.

Protocol references: [Meta subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions),
[Meta MSP usage schema](https://github.com/meta-models/muse-code-sdk/blob/main/schema/msp/msp.d.ts),
and the [CodexBar Muse adapter](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Resources/Plugins/muse.ts)
for the CLI endpoint and credential shape. Fixture tests validate parsing,
request construction, and account isolation. Live authentication still requires
a signed-in Muse CLI; the endpoint is not a stable public API contract.

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
Codex uses a neutral palette, with gray distinguishing its short-term quota.
Claude, Grok, and Antigravity use the existing CodexIsland display colors.
Muse Code uses the Meta symbol with its original blue gradient, and the
`#0082FB` blue from that symbol for charts and peek.

| Provider | Color | Hex |
| --- | --- | --- |
| Claude | Terracotta | `#CC785C` |
| Codex | Neutral white | `#E5E5E5` |
| Grok | White | `#FFFFFF` |
| Antigravity | Lilac | `#B69CFF` |
| Muse Code | Meta blue | `#0082FB` |

Antigravity uses a separate hue from Codex so adjacent providers are recognizable
at a glance. Green, amber, and red remain reserved for status and alerts. Keep
provider names and distinct marks visible so identification never depends only
on color.

## Demo mode

`CODEXISLAND_DEMO=1` also supplies synthetic Grok and Antigravity cost totals,
cumulative trends, and overview token history. VALUE uses illustrative monthly
plan baselines ($30 and $19.99 respectively) only in demo mode. These fixtures
never write the real cost cache or establish live subscription prices.
