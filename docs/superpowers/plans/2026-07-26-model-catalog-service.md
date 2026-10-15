# Model Catalog Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a bot-maintained, publicly auditable model price catalog at `https://ericjypark.github.io/codex-island-model-catalog/v1/models.json` so the macOS app stops needing a release per new model.

**Architecture:** A Go binary runs as a k3s CronJob every 6 hours on the maintainer's Raspberry Pi. It clones the catalog repo, fetches LiteLLM's price table, selects and converts the models we track, applies hand-maintained overrides, runs a sanity gate, and commits `v1/models.json` only when the price data actually changed. GitHub Pages serves the file. Nothing on the Pi is reachable from the internet.

**Tech Stack:** Go 1.26 (standard library only), Docker, k3s, GitHub Actions, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-07-26-model-list-api-design.md` (in the `codex-island` repo).

**Companion plan:** `2026-07-26-model-catalog-app-client.md` implements the macOS consumer. It can be built in parallel — the app falls back to its embedded seed until this service is live.

## Global Constraints

> **Repo split, decided after Task 6.** Tasks 1–6 were built in a single repo
> and then split, because publishing the k8s manifests would expose the shape
> of a personal deployment — namespace, secret name, schedule, image path —
> which the app repo's own `CLAUDE.md` says belongs in maintainer-only
> storage. The code needed no change: `cmd/sync` already reads everything from
> `REPO_DIR`, and the entrypoint already clones that directory by URL. Task
> text below still reads as one repo; the file lists are what matter.
>
> - **`ericjypark/codex-island-model-catalog`** (public) — `v1/models.json`,
>   `overrides.json`, `config.json`, `.nojekyll`, `README.md`. The audit
>   surface and the PR surface.
> - **`ericjypark/codex-island-infra`** (private) — Go module
>   `github.com/ericjypark/codex-island-infra`, `Dockerfile`, CI, `k8s/`.
>   Builds `ghcr.io/ericjypark/codex-island-infra:<sha>`.

- **Working repos:** the two above. This plan does **not** touch the `codex-island` app repo.
- **Go standard library only.** No third-party modules. `go.mod` must have an empty `require` block.
- **Schema version is 1.** Any breaking payload change ships at `/v2/models.json`; `/v1/` keeps its shape forever.
- **The bot never removes a model.** If LiteLLM drops an entry, the published value stays.
- **`CanonicalID` and `DisplayName` must match `Pricing.swift` exactly.** The macOS app canonicalizes before lookup; a disagreement means silent lookup misses and $0 costs.
- **Container image:** `ghcr.io/ericjypark/codex-island-model-catalog:<git-sha>`, matching the `ghcr.io/ericjypark/<name>:<sha>` convention already used on this cluster.
- **Kubernetes namespace:** `codexisland`.
- **Commits:** Conventional Commits (`feat:`, `fix:`, `chore:`, `test:`, `docs:`). Never add `Co-Authored-By` lines.
- **Comments:** default to none. Only explain a WHY that is not obvious from the code.

---

### Task 1: Repo scaffold, canonical ids, and display names

The two pure functions that must byte-for-byte agree with the macOS app. Everything else depends on them, so they come first.

**Files:**
- Create: `go.mod`
- Create: `internal/catalog/catalog.go`
- Create: `internal/catalog/naming.go`
- Test: `internal/catalog/naming_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `catalog.Rates` struct — `DisplayName string`, `InputPerMillion`, `OutputPerMillion`, `CacheCreationPerMillion`, `CacheReadPerMillion` all `float64`
  - `catalog.Catalog` struct — `SchemaVersion int`, `GeneratedAt string`, `Source string`, `Models map[string]Rates`
  - `catalog.CanonicalID(raw string) string`
  - `catalog.DisplayName(canonical string) string`
  - `catalog.DateSuffix(raw string) string` — the stripped suffix, or `""` when there is none

- [ ] **Step 1: Clone the repo and create the module**

```bash
cd ~/Desktop/Projects
git clone https://github.com/ericjypark/codex-island-model-catalog.git
cd codex-island-model-catalog
go mod init github.com/ericjypark/codex-island-model-catalog
```

Edit `go.mod` so it reads exactly:

```
module github.com/ericjypark/codex-island-model-catalog

go 1.26
```

- [ ] **Step 2: Write the failing test**

Create `internal/catalog/naming_test.go`:

```go
package catalog

import "testing"

func TestCanonicalID(t *testing.T) {
	cases := []struct{ in, want string }{
		{"claude-haiku-4-5-20251001", "claude-haiku-4-5"},
		{"claude-opus-4-8", "claude-opus-4-8"},
		{"gpt-5.6", "gpt-5.6"},
		{"gpt-5.1-codex-max", "gpt-5.1-codex-max"},
		// Too short to carry a 9-char suffix.
		{"gpt-5", "gpt-5"},
		// Nine trailing chars, but not "-" + 8 digits.
		{"claude-opus-4-5-2025100x", "claude-opus-4-5-2025100x"},
		{"model-1234567", "model-1234567"},
	}
	for _, c := range cases {
		if got := CanonicalID(c.in); got != c.want {
			t.Errorf("CanonicalID(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestDateSuffix(t *testing.T) {
	if got := DateSuffix("claude-haiku-4-5-20251001"); got != "20251001" {
		t.Errorf("DateSuffix = %q, want 20251001", got)
	}
	if got := DateSuffix("claude-opus-4-8"); got != "" {
		t.Errorf("DateSuffix = %q, want empty", got)
	}
}

func TestDisplayName(t *testing.T) {
	cases := []struct{ in, want string }{
		{"claude-opus-4-7", "Opus 4.7"},
		{"claude-fable-5", "Fable 5"},
		{"claude-sonnet-4-5", "Sonnet 4.5"},
		{"gpt-5.6", "GPT-5.6"},
		{"gpt-5.1-codex-max", "GPT-5.1-codex-max"},
		{"o3-pro", "O3-pro"},
		{"o4-mini-high", "O4-mini-high"},
		{"something-else", "something-else"},
	}
	for _, c := range cases {
		if got := DisplayName(c.in); got != c.want {
			t.Errorf("DisplayName(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `go test ./internal/catalog/ -run 'TestCanonicalID|TestDateSuffix|TestDisplayName' -v`

Expected: FAIL — `undefined: CanonicalID`, `undefined: DateSuffix`, `undefined: DisplayName`.

- [ ] **Step 4: Write the types**

Create `internal/catalog/catalog.go`:

```go
package catalog

// Rates is the published per-million-token price set for one model.
type Rates struct {
	DisplayName             string  `json:"displayName"`
	InputPerMillion         float64 `json:"inputPerMillion"`
	OutputPerMillion        float64 `json:"outputPerMillion"`
	CacheCreationPerMillion float64 `json:"cacheCreationPerMillion"`
	CacheReadPerMillion     float64 `json:"cacheReadPerMillion"`
}

// Catalog is the exact shape of v1/models.json.
type Catalog struct {
	SchemaVersion int              `json:"schemaVersion"`
	GeneratedAt   string           `json:"generatedAt"`
	Source        string           `json:"source"`
	Models        map[string]Rates `json:"models"`
}

const SchemaVersion = 1
```

- [ ] **Step 5: Write the naming rules**

Create `internal/catalog/naming.go`:

```go
package catalog

import "strings"

// CanonicalID strips an Anthropic-style date suffix ("-20251001") so
// date-pinned releases collapse onto their base model.
//
// This mirrors Pricing.canonicalModel in the macOS app character for
// character. If the two ever disagree, the app looks up ids this file
// never publishes and silently prices them at $0.
func CanonicalID(raw string) string {
	if DateSuffix(raw) == "" {
		return raw
	}
	return raw[:len(raw)-9]
}

// DateSuffix returns the 8-digit date at the end of raw, or "" if the id
// does not end in "-" followed by exactly 8 digits.
func DateSuffix(raw string) string {
	if len(raw) <= 9 {
		return ""
	}
	tail := raw[len(raw)-9:]
	if tail[0] != '-' {
		return ""
	}
	for i := 1; i < len(tail); i++ {
		if tail[i] < '0' || tail[i] > '9' {
			return ""
		}
	}
	return tail[1:]
}

// DisplayName renders a canonical id for the app's per-model rows.
// Mirrors Pricing.prettyModelName.
func DisplayName(canonical string) string {
	if rest, ok := strings.CutPrefix(canonical, "claude-"); ok {
		family, version, found := strings.Cut(rest, "-")
		if !found {
			return capitalizeFirst(rest)
		}
		return capitalizeFirst(family) + " " + strings.ReplaceAll(version, "-", ".")
	}
	if rest, ok := strings.CutPrefix(canonical, "gpt-"); ok {
		return "GPT-" + rest
	}
	if len(canonical) > 1 && canonical[0] == 'o' && canonical[1] >= '0' && canonical[1] <= '9' {
		return "O" + canonical[1:]
	}
	return canonical
}

func capitalizeFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `go test ./internal/catalog/ -v`

Expected: PASS for all three tests.

- [ ] **Step 7: Commit**

```bash
git add go.mod internal/catalog/catalog.go internal/catalog/naming.go internal/catalog/naming_test.go
git commit -m "feat: add catalog types and canonical id/display name rules"
```

---

### Task 2: Fetch and convert LiteLLM's price table

**Files:**
- Create: `internal/litellm/litellm.go`
- Create: `config.json`
- Create: `internal/catalog/build.go`
- Test: `internal/catalog/build_test.go`

**Interfaces:**
- Consumes: `catalog.Rates`, `catalog.CanonicalID`, `catalog.DateSuffix`, `catalog.DisplayName` from Task 1.
- Produces:
  - `litellm.Entry` struct with `Mode string` and four `*float64` cost fields
  - `litellm.DefaultURL` constant
  - `litellm.Fetch(ctx context.Context, url string) (map[string]litellm.Entry, error)`
  - `catalog.Config` struct — `Patterns []string`
  - `catalog.Build(entries map[string]litellm.Entry, cfg Config) (map[string]Rates, []string)` — returns the converted models and a slice of human-readable conflict notes

- [ ] **Step 1: Write the failing test**

Create `internal/catalog/build_test.go`:

```go
package catalog

import (
	"testing"

	"github.com/ericjypark/codex-island-model-catalog/internal/litellm"
)

func f(v float64) *float64 { return &v }

var testCfg = Config{Patterns: []string{"claude-*", "gpt-5*", "o[0-9]*"}}

func TestBuildConvertsPerTokenToPerMillion(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		"claude-opus-4-8": {
			Mode:                        "chat",
			InputCostPerToken:           f(0.000005),
			OutputCostPerToken:          f(0.000025),
			CacheCreationInputTokenCost: f(0.00000625),
			CacheReadInputTokenCost:     f(0.0000005),
		},
	}, testCfg)

	r, ok := got["claude-opus-4-8"]
	if !ok {
		t.Fatal("claude-opus-4-8 missing")
	}
	if r.InputPerMillion != 5 || r.OutputPerMillion != 25 {
		t.Errorf("input/output = %v/%v, want 5/25", r.InputPerMillion, r.OutputPerMillion)
	}
	if r.CacheCreationPerMillion != 6.25 || r.CacheReadPerMillion != 0.5 {
		t.Errorf("cache write/read = %v/%v, want 6.25/0.5",
			r.CacheCreationPerMillion, r.CacheReadPerMillion)
	}
	if r.DisplayName != "Opus 4.8" {
		t.Errorf("displayName = %q, want %q", r.DisplayName, "Opus 4.8")
	}
}

func TestBuildCacheFallbacks(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		"gpt-5.4": {
			Mode:               "chat",
			InputCostPerToken:  f(0.0000025),
			OutputCostPerToken: f(0.000015),
		},
	}, testCfg)

	r := got["gpt-5.4"]
	// Cache writes bill at the input rate when upstream lists none.
	if r.CacheCreationPerMillion != 2.5 {
		t.Errorf("cacheCreation = %v, want 2.5 (input rate)", r.CacheCreationPerMillion)
	}
	if r.CacheReadPerMillion != 0 {
		t.Errorf("cacheRead = %v, want 0", r.CacheReadPerMillion)
	}
}

func TestBuildFilters(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		// Wrong mode.
		"claude-embed-1": {Mode: "embedding", InputCostPerToken: f(0.000001), OutputCostPerToken: f(0.000001)},
		// Provider-prefixed re-listing.
		"bedrock/claude-opus-4-8": {Mode: "chat", InputCostPerToken: f(0.000005), OutputCostPerToken: f(0.000025)},
		// Not a tracked pattern.
		"gemini-3-pro": {Mode: "chat", InputCostPerToken: f(0.000001), OutputCostPerToken: f(0.000001)},
		// LiteLLM's non-model documentation key.
		"sample_spec": {Mode: "chat", InputCostPerToken: f(0.000001), OutputCostPerToken: f(0.000001)},
		// Keeper.
		"gpt-5.6": {Mode: "chat", InputCostPerToken: f(0.000005), OutputCostPerToken: f(0.00003)},
	}, testCfg)

	if len(got) != 1 {
		t.Fatalf("got %d models, want 1: %v", len(got), got)
	}
	if _, ok := got["gpt-5.6"]; !ok {
		t.Errorf("gpt-5.6 missing, got %v", got)
	}
}

// The rates that expose the residue are the cheap ones — these three inputs
// are exactly the values that produced 0.049999999999999996,
// 0.39999999999999997 and 0.19999999999999998 in the first bootstrap.
func TestBuildRoundsFloatResidue(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		"gpt-5.9-nano": {
			Mode:                        "chat",
			InputCostPerToken:           f(0.00000005),
			OutputCostPerToken:          f(0.0000004),
			CacheCreationInputTokenCost: f(0.0000004),
			CacheReadInputTokenCost:     f(0.0000002),
		},
	}, testCfg)

	r := got["gpt-5.9-nano"]
	if r.InputPerMillion != 0.05 {
		t.Errorf("input = %v, want exactly 0.05", r.InputPerMillion)
	}
	if r.OutputPerMillion != 0.4 {
		t.Errorf("output = %v, want exactly 0.4", r.OutputPerMillion)
	}
	// Set explicitly, so this covers the assignment inside the
	// CacheCreationInputTokenCost branch rather than the "= input" fallback.
	// That branch is live for every Anthropic model in the catalog.
	if r.CacheCreationPerMillion != 0.4 {
		t.Errorf("cacheCreation = %v, want exactly 0.4", r.CacheCreationPerMillion)
	}
	if r.CacheReadPerMillion != 0.2 {
		t.Errorf("cacheRead = %v, want exactly 0.2", r.CacheReadPerMillion)
	}
}

func TestBuildRequiresBothBaseRates(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		"gpt-5.9": {Mode: "chat", InputCostPerToken: f(0.000005)},
	}, testCfg)
	if len(got) != 0 {
		t.Errorf("entry without an output rate should be skipped, got %v", got)
	}
}

func TestBuildDedupesDatedVariants(t *testing.T) {
	got, notes := Build(map[string]litellm.Entry{
		"claude-haiku-4-5": {
			Mode: "chat", InputCostPerToken: f(0.000001), OutputCostPerToken: f(0.000005),
		},
		"claude-haiku-4-5-20251001": {
			Mode: "chat", InputCostPerToken: f(0.000009), OutputCostPerToken: f(0.000005),
		},
	}, testCfg)

	if len(got) != 1 {
		t.Fatalf("dated variant should collapse onto the base id, got %v", got)
	}
	// The bare id is the alias that tracks latest, so it wins.
	if got["claude-haiku-4-5"].InputPerMillion != 1 {
		t.Errorf("input = %v, want 1 (bare id wins)", got["claude-haiku-4-5"].InputPerMillion)
	}
	if len(notes) == 0 {
		t.Error("disagreeing variants should produce a conflict note")
	}
}

func TestBuildPrefersNewestDateWhenNoBareID(t *testing.T) {
	got, _ := Build(map[string]litellm.Entry{
		"claude-opus-9-1-20250101": {
			Mode: "chat", InputCostPerToken: f(0.000001), OutputCostPerToken: f(0.000001),
		},
		"claude-opus-9-1-20260101": {
			Mode: "chat", InputCostPerToken: f(0.000007), OutputCostPerToken: f(0.000001),
		},
	}, testCfg)

	if got["claude-opus-9-1"].InputPerMillion != 7 {
		t.Errorf("input = %v, want 7 (newest date wins)", got["claude-opus-9-1"].InputPerMillion)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./internal/catalog/ -run TestBuild -v`

Expected: FAIL — the `internal/litellm` package does not exist yet.

- [ ] **Step 3: Write the LiteLLM client**

Create `internal/litellm/litellm.go`:

```go
package litellm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const DefaultURL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

// Entry is the subset of LiteLLM's per-model record this catalog reads.
// Costs are pointers so an absent key is distinguishable from a real zero.
type Entry struct {
	Mode                        string   `json:"mode"`
	InputCostPerToken           *float64 `json:"input_cost_per_token"`
	OutputCostPerToken          *float64 `json:"output_cost_per_token"`
	CacheCreationInputTokenCost *float64 `json:"cache_creation_input_token_cost"`
	CacheReadInputTokenCost     *float64 `json:"cache_read_input_token_cost"`
}

func Fetch(ctx context.Context, url string) (map[string]Entry, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("litellm: HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return nil, err
	}
	var out map[string]Entry
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, fmt.Errorf("litellm: decode: %w", err)
	}
	return out, nil
}
```

- [ ] **Step 4: Write the builder**

Create `internal/catalog/build.go`:

```go
package catalog

import (
	"fmt"
	"math"
	"path"
	"strings"

	"github.com/ericjypark/codex-island-model-catalog/internal/litellm"
)

// Config is the shape of config.json.
type Config struct {
	Patterns []string `json:"patterns"`
}

// Build converts upstream entries into published rates. The second return
// value carries notes about date-pinned variants that disagreed on price.
func Build(entries map[string]litellm.Entry, cfg Config) (map[string]Rates, []string) {
	type candidate struct {
		rates Rates
		date  string
	}
	best := map[string]candidate{}
	var notes []string

	for id, e := range entries {
		if !tracked(id, e, cfg) {
			continue
		}
		canonical := CanonicalID(id)
		date := DateSuffix(id)
		next := candidate{rates: convert(canonical, e), date: date}

		prev, seen := best[canonical]
		if !seen {
			best[canonical] = next
			continue
		}
		if prev.rates != next.rates {
			notes = append(notes, fmt.Sprintf(
				"%s: variants disagree (%s=%v vs %s=%v)",
				canonical, variantLabel(prev.date), prev.rates.InputPerMillion,
				variantLabel(next.date), next.rates.InputPerMillion))
		}
		if wins(next.date, prev.date) {
			best[canonical] = next
		}
	}

	out := make(map[string]Rates, len(best))
	for id, c := range best {
		out[id] = c.rates
	}
	return out, notes
}

// wins reports whether date a beats date b. The bare id (empty date) is the
// alias upstream keeps pointed at the current release, so it outranks every
// pinned variant; otherwise the later date wins.
func wins(a, b string) bool {
	if a == "" {
		return true
	}
	if b == "" {
		return false
	}
	return a > b
}

func variantLabel(date string) string {
	if date == "" {
		return "bare"
	}
	return date
}

// ValidateConfig rejects a malformed pattern up front. path.Match reports a
// bad pattern only as an error return, so a typo in config.json would
// otherwise make an entire provider's models vanish from the catalog with no
// signal at all — and the run-level count check would be the only thing that
// noticed.
func ValidateConfig(cfg Config) error {
	for _, p := range cfg.Patterns {
		if _, err := path.Match(p, "validate"); err != nil {
			return fmt.Errorf("config: bad pattern %q: %w", p, err)
		}
	}
	return nil
}

func tracked(id string, e litellm.Entry, cfg Config) bool {
	if id == "sample_spec" || strings.Contains(id, "/") {
		return false
	}
	if e.Mode != "chat" && e.Mode != "responses" {
		return false
	}
	if e.InputCostPerToken == nil || e.OutputCostPerToken == nil {
		return false
	}
	for _, p := range cfg.Patterns {
		if ok, _ := path.Match(p, id); ok {
			return true
		}
	}
	return false
}

// perMillion converts a per-token price and rounds off the binary-float
// residue the multiplication leaves behind: 2e-7 * 1e6 lands on
// 0.19999999999999998, which would be published verbatim into a file whose
// entire point is that a human can read a price and check it against the
// vendor's page. Eight decimals is far finer than any real rate and coarse
// enough to erase the artifact.
func perMillion(perToken float64) float64 {
	return math.Round(perToken*1e6*1e8) / 1e8
}

func convert(canonical string, e litellm.Entry) Rates {
	input := perMillion(*e.InputCostPerToken)
	r := Rates{
		DisplayName:             DisplayName(canonical),
		InputPerMillion:         input,
		OutputPerMillion:        perMillion(*e.OutputCostPerToken),
		CacheCreationPerMillion: input,
	}
	if e.CacheCreationInputTokenCost != nil {
		r.CacheCreationPerMillion = perMillion(*e.CacheCreationInputTokenCost)
	}
	if e.CacheReadInputTokenCost != nil {
		r.CacheReadPerMillion = perMillion(*e.CacheReadInputTokenCost)
	}
	return r
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `go test ./... -v`

Expected: PASS for every test in `internal/catalog`.

- [ ] **Step 6: Create the pattern config**

Create `config.json`:

```json
{
  "patterns": [
    "claude-*",
    "gpt-5*",
    "o[0-9]*"
  ]
}
```

- [ ] **Step 7: Commit**

```bash
git add config.json internal/litellm/litellm.go internal/catalog/build.go internal/catalog/build_test.go
git commit -m "feat: convert litellm price table into catalog rates"
```

---

### Task 3: Hand-maintained overrides

**Files:**
- Create: `internal/catalog/overrides.go`
- Create: `overrides.json`
- Test: `internal/catalog/overrides_test.go`

**Interfaces:**
- Consumes: `catalog.Rates` from Task 1.
- Produces:
  - `catalog.Override` struct — `DisplayName *string`, and `*float64` for each of the four rates
  - `catalog.ApplyOverrides(base map[string]Rates, ov map[string]Override) map[string]Rates`

- [ ] **Step 1: Write the failing test**

Create `internal/catalog/overrides_test.go`:

```go
package catalog

import "testing"

func s(v string) *string { return &v }

func TestApplyOverridesPerField(t *testing.T) {
	base := map[string]Rates{
		"gpt-5.6": {
			DisplayName: "GPT-5.6", InputPerMillion: 5, OutputPerMillion: 30,
			CacheCreationPerMillion: 5, CacheReadPerMillion: 0.5,
		},
	}
	got := ApplyOverrides(base, map[string]Override{
		"gpt-5.6": {CacheCreationPerMillion: f(6.25)},
	})

	r := got["gpt-5.6"]
	if r.CacheCreationPerMillion != 6.25 {
		t.Errorf("cacheCreation = %v, want 6.25", r.CacheCreationPerMillion)
	}
	if r.InputPerMillion != 5 || r.OutputPerMillion != 30 || r.CacheReadPerMillion != 0.5 {
		t.Errorf("untouched fields changed: %+v", r)
	}
}

func TestApplyOverridesZeroIsRespected(t *testing.T) {
	base := map[string]Rates{"gpt-5-pro": {InputPerMillion: 15, CacheReadPerMillion: 1.5}}
	got := ApplyOverrides(base, map[string]Override{
		"gpt-5-pro": {CacheReadPerMillion: f(0)},
	})
	if got["gpt-5-pro"].CacheReadPerMillion != 0 {
		t.Errorf("explicit zero override was dropped: %+v", got["gpt-5-pro"])
	}
}

func TestApplyOverridesDisplayName(t *testing.T) {
	base := map[string]Rates{"gpt-5.6-sol": {DisplayName: "GPT-5.6-sol", InputPerMillion: 5}}
	got := ApplyOverrides(base, map[string]Override{
		"gpt-5.6-sol": {DisplayName: s("GPT-5.6 Sol")},
	})
	if got["gpt-5.6-sol"].DisplayName != "GPT-5.6 Sol" {
		t.Errorf("displayName = %q", got["gpt-5.6-sol"].DisplayName)
	}
}

func TestApplyOverridesAddsModelAbsentUpstream(t *testing.T) {
	got := ApplyOverrides(map[string]Rates{}, map[string]Override{
		"gpt-5.6-luna": {
			DisplayName: s("GPT-5.6 Luna"), InputPerMillion: f(1), OutputPerMillion: f(6),
			CacheCreationPerMillion: f(1.25), CacheReadPerMillion: f(0.1),
		},
	})
	r, ok := got["gpt-5.6-luna"]
	if !ok {
		t.Fatal("override-only model missing")
	}
	if r.InputPerMillion != 1 || r.OutputPerMillion != 6 {
		t.Errorf("override-only rates wrong: %+v", r)
	}
}

func TestApplyOverridesFillsMissingDisplayName(t *testing.T) {
	got := ApplyOverrides(map[string]Rates{}, map[string]Override{
		"claude-opus-9-9": {InputPerMillion: f(1), OutputPerMillion: f(2)},
	})
	if got["claude-opus-9-9"].DisplayName != "Opus 9.9" {
		t.Errorf("displayName = %q, want generated %q",
			got["claude-opus-9-9"].DisplayName, "Opus 9.9")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./internal/catalog/ -run TestApplyOverrides -v`

Expected: FAIL — `undefined: ApplyOverrides`, `undefined: Override`.

- [ ] **Step 3: Write the implementation**

Create `internal/catalog/overrides.go`:

```go
package catalog

// Override is a partial Rates. Every field is a pointer so that an absent
// key and an explicit zero stay distinguishable — "cacheReadPerMillion": 0
// is a real statement about a model that has no prompt caching.
type Override struct {
	DisplayName             *string  `json:"displayName,omitempty"`
	InputPerMillion         *float64 `json:"inputPerMillion,omitempty"`
	OutputPerMillion        *float64 `json:"outputPerMillion,omitempty"`
	CacheCreationPerMillion *float64 `json:"cacheCreationPerMillion,omitempty"`
	CacheReadPerMillion     *float64 `json:"cacheReadPerMillion,omitempty"`
}

// ApplyOverrides layers hand-maintained values over the upstream-derived
// ones. An override always wins, and may introduce a model upstream has
// never listed.
func ApplyOverrides(base map[string]Rates, ov map[string]Override) map[string]Rates {
	out := make(map[string]Rates, len(base)+len(ov))
	for id, r := range base {
		out[id] = r
	}
	for id, o := range ov {
		r := out[id]
		if o.DisplayName != nil {
			r.DisplayName = *o.DisplayName
		}
		if o.InputPerMillion != nil {
			r.InputPerMillion = *o.InputPerMillion
		}
		if o.OutputPerMillion != nil {
			r.OutputPerMillion = *o.OutputPerMillion
		}
		if o.CacheCreationPerMillion != nil {
			r.CacheCreationPerMillion = *o.CacheCreationPerMillion
		}
		if o.CacheReadPerMillion != nil {
			r.CacheReadPerMillion = *o.CacheReadPerMillion
		}
		if r.DisplayName == "" {
			r.DisplayName = DisplayName(id)
		}
		out[id] = r
	}
	return out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... -v`

Expected: PASS.

- [ ] **Step 5: Seed overrides.json with the app's existing deviations**

These are the values `Sources/Cost/Pricing.swift` carries today that LiteLLM either does not list or lists differently. Create `overrides.json`:

```json
{
  "gpt-5.6": { "cacheCreationPerMillion": 6.25 },
  "gpt-5.6-sol": {
    "displayName": "GPT-5.6 Sol",
    "inputPerMillion": 5,
    "outputPerMillion": 30,
    "cacheCreationPerMillion": 6.25,
    "cacheReadPerMillion": 0.5
  },
  "gpt-5.6-terra": {
    "displayName": "GPT-5.6 Terra",
    "inputPerMillion": 2.5,
    "outputPerMillion": 15,
    "cacheCreationPerMillion": 3.125,
    "cacheReadPerMillion": 0.25
  },
  "gpt-5.6-luna": {
    "displayName": "GPT-5.6 Luna",
    "inputPerMillion": 1,
    "outputPerMillion": 6,
    "cacheCreationPerMillion": 1.25,
    "cacheReadPerMillion": 0.1
  },
  "gpt-5.2-pro": { "cacheReadPerMillion": 0 },
  "gpt-5-pro": { "cacheReadPerMillion": 0 }
}
```

- [ ] **Step 6: Commit**

```bash
git add overrides.json internal/catalog/overrides.go internal/catalog/overrides_test.go
git commit -m "feat: layer hand-maintained overrides over upstream rates"
```

---

### Task 4: Sanity gate

The app release cycle used to be an implicit review gate on every price change. This replaces it, so it gets the densest test coverage in the plan.

**Files:**
- Create: `internal/catalog/gate.go`
- Test: `internal/catalog/gate_test.go`

**Interfaces:**
- Consumes: `catalog.Rates` from Task 1.
- Produces:
  - `catalog.GateResult` struct — `Models map[string]Rates`, `Rejections []string`, `Aborted bool`, `AbortReason string`
  - `catalog.Gate(candidate, published map[string]Rates) GateResult`

- [ ] **Step 1: Write the failing test**

Create `internal/catalog/gate_test.go`:

```go
package catalog

import "testing"

func rate(in, out float64) Rates {
	return Rates{
		DisplayName: "X", InputPerMillion: in, OutputPerMillion: out,
		CacheCreationPerMillion: in, CacheReadPerMillion: in / 10,
	}
}

func TestGateAbortsOnCountCollapse(t *testing.T) {
	published := map[string]Rates{
		"a": rate(1, 2), "b": rate(1, 2), "c": rate(1, 2), "d": rate(1, 2),
	}
	got := Gate(map[string]Rates{"a": rate(1, 2)}, published)
	if !got.Aborted {
		t.Fatal("1 of 4 models should abort the run")
	}
	if got.AbortReason == "" {
		t.Error("abort should carry a reason")
	}
}

func TestGateAllowsHalfExactly(t *testing.T) {
	published := map[string]Rates{"a": rate(1, 2), "b": rate(1, 2)}
	got := Gate(map[string]Rates{"a": rate(1, 2)}, published)
	if got.Aborted {
		t.Error("exactly half should not abort")
	}
}

func TestGateFirstRunNeverAborts(t *testing.T) {
	got := Gate(map[string]Rates{"a": rate(1, 2)}, map[string]Rates{})
	if got.Aborted {
		t.Error("bootstrapping against an empty catalog must not abort")
	}
	// Without this, a gate that rejected every baseline-less model would
	// still pass: the catalog would silently stop accepting new models.
	if _, ok := got.Models["a"]; !ok {
		t.Error("a valid brand-new model must be published")
	}
}

func TestGateAbortKeepsPublishedRatherThanEmptying(t *testing.T) {
	published := map[string]Rates{
		"a": rate(1, 2), "b": rate(1, 2), "c": rate(1, 2), "d": rate(1, 2),
	}
	got := Gate(map[string]Rates{"a": rate(1, 2)}, published)
	if !got.Aborted {
		t.Fatal("expected abort")
	}
	if len(got.Models) != len(published) {
		t.Errorf("abort returned %d models, want the published %d — an empty "+
			"map would price everything at $0 for any caller that skips the "+
			"Aborted check", len(got.Models), len(published))
	}
}

// Zero baseline routes past the ratio rule, so the negative check is the
// only rule that can reject this. Without it the test would pass even with
// the negative check deleted.
func TestGateRejectsNegativeRate(t *testing.T) {
	published := map[string]Rates{"a": {InputPerMillion: 1, OutputPerMillion: 2, CacheReadPerMillion: 0}}
	candidate := map[string]Rates{"a": {InputPerMillion: 1, OutputPerMillion: 2, CacheReadPerMillion: -0.1}}
	got := Gate(candidate, published)
	if got.Models["a"].CacheReadPerMillion != 0 {
		t.Errorf("negative rate should keep the published value, got %v", got.Models["a"])
	}
	if len(got.Rejections) == 0 {
		t.Error("rejection should be recorded")
	}
}

// The cap is checked before the ratio rule (it has to be — the ratio rule is
// skipped for baseline-less models, and the cap must not be). So this pins
// the baselined-above-cap path: rejected, but kept at its published value
// rather than omitted. TestGateRejectsTenfoldJump covers the ratio rule.
func TestGateRejectsAboveCapKeepsPublished(t *testing.T) {
	published := map[string]Rates{"a": rate(5, 10)}
	got := Gate(map[string]Rates{"a": rate(1001, 10)}, published)
	if got.Models["a"].InputPerMillion != 5 {
		t.Errorf("above-cap rate should keep published value, got %v", got.Models["a"])
	}
}

// The cap is the entire defense for a model with no baseline, so it is
// tested there — and on a non-input field, since the ratio rule that covers
// the other three is skipped in exactly this case.
func TestGateOmitsAbsurdBrandNewModel(t *testing.T) {
	got := Gate(map[string]Rates{
		"a":       rate(1, 2),
		"new":     {InputPerMillion: 5001, OutputPerMillion: 10, CacheCreationPerMillion: 5, CacheReadPerMillion: 0.5},
		"newout":  {InputPerMillion: 5, OutputPerMillion: 1000000, CacheCreationPerMillion: 5, CacheReadPerMillion: 0.5},
		"atlimit": {InputPerMillion: 1000, OutputPerMillion: 10, CacheCreationPerMillion: 5, CacheReadPerMillion: 0.5},
	}, map[string]Rates{"a": rate(1, 2)})

	if _, ok := got.Models["new"]; ok {
		t.Error("brand-new model above the input cap must be omitted")
	}
	if _, ok := got.Models["newout"]; ok {
		t.Error("brand-new model above the output cap must be omitted")
	}
	if _, ok := got.Models["atlimit"]; !ok {
		t.Error("exactly at the cap must survive — the bound is exclusive")
	}
	if _, ok := got.Models["a"]; !ok {
		t.Error("the valid model must survive; the gate rejected everything")
	}
	if len(got.Rejections) != 2 {
		t.Errorf("want 2 rejections, got %v", got.Rejections)
	}
}

func TestGateRejectsTenfoldJump(t *testing.T) {
	published := map[string]Rates{"a": rate(5, 10)}
	got := Gate(map[string]Rates{"a": rate(50, 10)}, published)
	if got.Models["a"].InputPerMillion != 5 {
		t.Errorf("10x jump should keep published value, got %v", got.Models["a"])
	}
}

func TestGateRejectsTenfoldDrop(t *testing.T) {
	published := map[string]Rates{"a": rate(50, 10)}
	got := Gate(map[string]Rates{"a": rate(5, 10)}, published)
	if got.Models["a"].InputPerMillion != 50 {
		t.Errorf("10x drop should keep published value, got %v", got.Models["a"])
	}
}

func TestGateAllowsOrdinaryPriceChange(t *testing.T) {
	published := map[string]Rates{"a": rate(3, 15)}
	got := Gate(map[string]Rates{"a": rate(2, 10)}, published)
	if got.Models["a"].InputPerMillion != 2 {
		t.Errorf("a 33%% cut should pass, got %v", got.Models["a"])
	}
	if len(got.Rejections) != 0 {
		t.Errorf("no rejection expected, got %v", got.Rejections)
	}
}

func TestGateSkipsRatioRuleWhenPublishedIsZero(t *testing.T) {
	published := map[string]Rates{"a": {InputPerMillion: 5, OutputPerMillion: 10, CacheReadPerMillion: 0}}
	candidate := map[string]Rates{"a": {InputPerMillion: 5, OutputPerMillion: 10, CacheReadPerMillion: 0.5}}
	got := Gate(candidate, published)
	if got.Models["a"].CacheReadPerMillion != 0.5 {
		t.Errorf("a rate moving off zero must be allowed, got %v", got.Models["a"])
	}
}

func TestGateOmitsBadBrandNewModel(t *testing.T) {
	got := Gate(map[string]Rates{"a": rate(1, 2), "b": rate(-3, 2)}, map[string]Rates{"a": rate(1, 2)})
	if _, ok := got.Models["b"]; ok {
		t.Error("a new model with a bad rate should be omitted, not published")
	}
}

func TestGateCarriesForwardModelsDroppedUpstream(t *testing.T) {
	published := map[string]Rates{"a": rate(1, 2), "gone": rate(9, 9)}
	got := Gate(map[string]Rates{"a": rate(1, 2)}, published)
	if _, ok := got.Models["gone"]; !ok {
		t.Error("a model dropped upstream must survive in the output")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./internal/catalog/ -run TestGate -v`

Expected: FAIL — `undefined: Gate`.

- [ ] **Step 3: Write the implementation**

Create `internal/catalog/gate.go`:

```go
package catalog

import "fmt"

const (
	maxPerMillion  = 1000.0
	maxRatioChange = 10.0
)

type GateResult struct {
	Models      map[string]Rates
	Rejections  []string
	Aborted     bool
	AbortReason string
}

// Gate is the review step that the app release cycle used to provide. It
// decides what is safe to publish given what is already published.
//
// A rejected model keeps its published values rather than disappearing:
// dropping it would price it at $0, which is the exact failure this whole
// design exists to prevent.
func Gate(candidate, published map[string]Rates) GateResult {
	res := GateResult{Models: make(map[string]Rates, len(candidate)+len(published))}

	if n := len(published); n > 0 && len(candidate)*2 < n {
		// Hand back what is already published, never an empty map: a caller
		// that forgets to check Aborted must produce a no-op, not a catalog
		// of zero models — which would price everything at $0 in the app.
		res.Models = published
		res.Aborted = true
		res.AbortReason = fmt.Sprintf(
			"model count collapsed: %d candidates against %d published", len(candidate), n)
		return res
	}

	for id, r := range candidate {
		prev, hadPrev := published[id]
		if reason := check(r, prev, hadPrev); reason != "" {
			res.Rejections = append(res.Rejections, fmt.Sprintf("%s: %s", id, reason))
			if hadPrev {
				res.Models[id] = prev
			}
			continue
		}
		res.Models[id] = r
	}

	// Upstream removals never propagate.
	for id, r := range published {
		if _, ok := res.Models[id]; !ok {
			res.Models[id] = r
		}
	}
	return res
}

func check(next, prev Rates, hadPrev bool) string {
	fields := []struct {
		name       string
		next, prev float64
	}{
		{"inputPerMillion", next.InputPerMillion, prev.InputPerMillion},
		{"outputPerMillion", next.OutputPerMillion, prev.OutputPerMillion},
		{"cacheCreationPerMillion", next.CacheCreationPerMillion, prev.CacheCreationPerMillion},
		{"cacheReadPerMillion", next.CacheReadPerMillion, prev.CacheReadPerMillion},
	}
	for _, f := range fields {
		if f.next < 0 {
			return fmt.Sprintf("%s is negative (%v)", f.name, f.next)
		}
		// The absolute ceiling applies to every rate, not just input. For a
		// brand-new model the ratio rule below is skipped entirely, so this
		// is the only bound that rule ever sees — and output tokens dominate
		// the app's spend arithmetic.
		if f.next > maxPerMillion {
			return fmt.Sprintf("%s %v exceeds %v", f.name, f.next, maxPerMillion)
		}
		if !hadPrev || f.prev <= 0 {
			// No baseline, or a rate legitimately moving off zero — the
			// ratio test has nothing meaningful to say.
			continue
		}
		if f.next >= f.prev*maxRatioChange || f.next*maxRatioChange <= f.prev {
			return fmt.Sprintf("%s moved %v -> %v", f.name, f.prev, f.next)
		}
	}
	return ""
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... -v`

Expected: PASS for all gate tests.

- [ ] **Step 5: Commit**

```bash
git add internal/catalog/gate.go internal/catalog/gate_test.go
git commit -m "feat: add sanity gate guarding published price changes"
```

---

### Task 5: Sync command and change detection

**Files:**
- Create: `internal/catalog/encode.go`
- Modify: `internal/catalog/overrides.go` (add `ValidateOverrides`)
- Create: `cmd/sync/main.go`
- Create: `v1/models.json`
- Create: `.nojekyll`
- Test: `internal/catalog/encode_test.go`, `internal/catalog/overrides_test.go`

**Interfaces:**
- Consumes: everything from Tasks 1–4. The test below reuses the `rate(in, out float64) Rates` helper defined in `gate_test.go` (Task 4) — same package, so Task 4 must land first.
- Produces:
  - `catalog.Encode(c Catalog) ([]byte, error)` — deterministic, indented, newline-terminated
  - `catalog.Decode(b []byte) (Catalog, error)`
  - `catalog.ModelsEqual(a, b map[string]Rates) bool`

- [ ] **Step 1: Write the failing test**

Create `internal/catalog/encode_test.go`:

```go
package catalog

import (
	"bytes"
	"testing"
)

func TestEncodeIsDeterministic(t *testing.T) {
	c := Catalog{
		SchemaVersion: SchemaVersion,
		GeneratedAt:   "2026-07-26T01:00:00Z",
		Source:        "test",
		Models: map[string]Rates{
			"zeta": rate(1, 2), "alpha": rate(3, 4), "mid": rate(5, 6),
		},
	}
	first, err := Encode(c)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 20; i++ {
		again, err := Encode(c)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(first, again) {
			t.Fatal("Encode is not deterministic across runs")
		}
	}
	if !bytes.HasSuffix(first, []byte("\n")) {
		t.Error("encoded catalog should end with a newline")
	}
}

func TestEncodeDecodeRoundTrip(t *testing.T) {
	c := Catalog{
		SchemaVersion: SchemaVersion,
		GeneratedAt:   "2026-07-26T01:00:00Z",
		Source:        "test",
		Models:        map[string]Rates{"claude-opus-4-8": rate(5, 25)},
	}
	b, err := Encode(c)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Decode(b)
	if err != nil {
		t.Fatal(err)
	}
	if got.SchemaVersion != SchemaVersion || !ModelsEqual(got.Models, c.Models) {
		t.Errorf("round trip lost data: %+v", got)
	}
}

func TestDecodeMissingFileShapeIsAnError(t *testing.T) {
	if _, err := Decode([]byte("not json")); err == nil {
		t.Error("garbage input should error")
	}
}

func TestModelsEqualIgnoresTimestamp(t *testing.T) {
	a := map[string]Rates{"x": rate(1, 2)}
	b := map[string]Rates{"x": rate(1, 2)}
	if !ModelsEqual(a, b) {
		t.Error("identical model maps should compare equal")
	}
	b["x"] = rate(1, 3)
	if ModelsEqual(a, b) {
		t.Error("differing rates should compare unequal")
	}
	if ModelsEqual(a, map[string]Rates{}) {
		t.Error("different sizes should compare unequal")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go test ./internal/catalog/ -run 'TestEncode|TestDecode|TestModelsEqual' -v`

Expected: FAIL — `undefined: Encode`, `undefined: Decode`, `undefined: ModelsEqual`.

- [ ] **Step 2b: Write the failing test for override validation**

Because `cmd/sync` re-applies overrides *after* the gate, override values never
pass through `check` — that is what makes them an escape hatch, and it also
means nothing stands between a typo and the published catalog. Bounding their
magnitude again would close the hatch, so only the unambiguous error is caught.

Add to `internal/catalog/overrides_test.go`:

```go
func TestValidateOverrides(t *testing.T) {
	ok := map[string]Override{
		"a": {InputPerMillion: f(5), CacheReadPerMillion: f(0)},
		// Deliberately far above the gate's cap: an override exists so a
		// legitimately expensive model can exceed it.
		"b": {OutputPerMillion: f(5000)},
	}
	if err := ValidateOverrides(ok); err != nil {
		t.Errorf("valid overrides rejected: %v", err)
	}

	bad := map[string]Override{"c": {CacheReadPerMillion: f(-0.1)}}
	err := ValidateOverrides(bad)
	if err == nil {
		t.Fatal("negative override should be rejected")
	}
	if !strings.Contains(err.Error(), "c") {
		t.Errorf("error should name the offending model, got %v", err)
	}
}
```

- [ ] **Step 2c: Implement `ValidateOverrides`**

Append to `internal/catalog/overrides.go`:

```go
// ValidateOverrides rejects values that cannot be anything but a typo.
//
// Magnitude is deliberately unbounded. An override's whole purpose is to let
// a legitimately expensive model exceed the gate's absolute cap, and it is
// applied after the gate for that reason — re-bounding it here would close
// the escape hatch. Review of the public PR that changes overrides.json is
// the control on magnitude. A negative rate, though, is never intentional.
func ValidateOverrides(ov map[string]Override) error {
	for id, o := range ov {
		fields := []struct {
			name string
			val  *float64
		}{
			{"inputPerMillion", o.InputPerMillion},
			{"outputPerMillion", o.OutputPerMillion},
			{"cacheCreationPerMillion", o.CacheCreationPerMillion},
			{"cacheReadPerMillion", o.CacheReadPerMillion},
		}
		for _, f := range fields {
			if f.val != nil && *f.val < 0 {
				return fmt.Errorf("overrides: %s: %s is negative (%v)", id, f.name, *f.val)
			}
		}
	}
	return nil
}
```

`overrides.go` gains a `fmt` import.

- [ ] **Step 3: Write the implementation**

Create `internal/catalog/encode.go`:

```go
package catalog

import (
	"encoding/json"
	"maps"
)

// Encode renders a catalog for commit. encoding/json sorts map keys, so
// byte-identical input yields byte-identical output and the change check
// in cmd/sync stays honest.
func Encode(c Catalog) ([]byte, error) {
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

func Decode(b []byte) (Catalog, error) {
	var c Catalog
	if err := json.Unmarshal(b, &c); err != nil {
		return Catalog{}, err
	}
	return c, nil
}

// ModelsEqual compares only the price data. GeneratedAt is deliberately
// excluded: including it would make every run differ and produce a commit
// every six hours forever.
func ModelsEqual(a, b map[string]Rates) bool {
	return maps.Equal(a, b)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go test ./... -v`

Expected: PASS.

- [ ] **Step 5: Write the sync command**

Create `cmd/sync/main.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/ericjypark/codex-island-model-catalog/internal/catalog"
	"github.com/ericjypark/codex-island-model-catalog/internal/litellm"
)

const catalogPath = "v1/models.json"

func main() {
	if err := run(); err != nil {
		log.Fatalf("sync: %v", err)
	}
}

func run() error {
	repo := os.Getenv("REPO_DIR")
	if repo == "" {
		repo = "."
	}

	cfg, err := readJSON[catalog.Config](filepath.Join(repo, "config.json"))
	if err != nil {
		return fmt.Errorf("config.json: %w", err)
	}
	if err := catalog.ValidateConfig(cfg); err != nil {
		return err
	}
	overrides, err := readJSON[map[string]catalog.Override](filepath.Join(repo, "overrides.json"))
	if err != nil {
		return fmt.Errorf("overrides.json: %w", err)
	}
	if err := catalog.ValidateOverrides(overrides); err != nil {
		return err
	}

	published := map[string]catalog.Rates{}
	raw, err := os.ReadFile(filepath.Join(repo, catalogPath))
	switch {
	case err == nil:
		prev, decErr := catalog.Decode(raw)
		if decErr != nil {
			return fmt.Errorf("%s: %w", catalogPath, decErr)
		}
		published = prev.Models
	case errors.Is(err, fs.ErrNotExist):
		// Genuine first run — an empty `published` is correct here.
	default:
		// Every other read error must stop the run. An empty `published`
		// silently disables the collapse abort (gated on len > 0), the ratio
		// rule (every model looks brand new), and the carry-forward loop that
		// implements "never remove a model" — so one transient I/O fault
		// would let a single upstream response overwrite the catalog whole.
		return fmt.Errorf("%s: %w", catalogPath, err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	url := litellm.DefaultURL
	if v := os.Getenv("LITELLM_URL"); v != "" {
		url = v
	}
	entries, err := litellm.Fetch(ctx, url)
	if err != nil {
		return err
	}

	built, notes := catalog.Build(entries, cfg)
	for _, n := range notes {
		log.Printf("conflict: %s", n)
	}

	gated := catalog.Gate(catalog.ApplyOverrides(built, overrides), published)
	for _, r := range gated.Rejections {
		log.Printf("rejected: %s", r)
	}
	if gated.Aborted {
		return fmt.Errorf("aborted: %s", gated.AbortReason)
	}

	// Overrides are re-asserted after the gate, and this is what makes them a
	// real escape hatch. The gate exists to stop bad *upstream* data; an
	// override is hand-written and reviewed in a public PR, so it is trusted
	// input. Without this second pass, a legitimately expensive model that
	// trips the absolute cap could not be corrected by hand — the gate would
	// reject the correction too, and the model would price at $0 forever.
	// They are also applied before the gate so the ratio rule compares like
	// with like against the published values.
	final := catalog.ApplyOverrides(gated.Models, overrides)

	if catalog.ModelsEqual(final, published) {
		log.Printf("no change (%d models)", len(final))
		return nil
	}

	out, err := catalog.Encode(catalog.Catalog{
		SchemaVersion: catalog.SchemaVersion,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
		Source:        "litellm + overrides",
		Models:        final,
	})
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(repo, catalogPath), out, 0o644); err != nil {
		return err
	}
	log.Printf("updated: %d models (was %d)", len(final), len(published))

	if os.Getenv("SKIP_COMMIT") != "" {
		return nil
	}
	return commit(repo, len(final))
}

func readJSON[T any](path string) (T, error) {
	var v T
	b, err := os.ReadFile(path)
	if err != nil {
		return v, err
	}
	err = json.Unmarshal(b, &v)
	return v, err
}

func commit(repo string, count int) error {
	// Identity travels per-invocation rather than through `git config`, which
	// writes at local scope and would permanently rewrite the bot identity
	// into whatever clone this runs in — including a maintainer's during
	// local iteration.
	ident := []string{
		"-c", "user.email=bot@codexisland.dev",
		"-c", "user.name=codexisland-catalog-bot",
	}
	// Named rather than derived from args[0]: the commit step leads with the
	// identity flags, so args[0] would report a failed commit as "git -c".
	steps := []struct {
		name string
		args []string
	}{
		{"add", []string{"add", catalogPath}},
		{"commit", append(append([]string{}, ident...),
			"commit", "-m", fmt.Sprintf("chore: refresh model catalog (%d models)", count))},
		{"push", []string{"push"}},
	}
	for _, step := range steps {
		cmd := exec.Command("git", append([]string{"-C", repo}, step.args...)...)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("git %s: %w", step.name, err)
		}
	}
	return nil
}
```

- [ ] **Step 6: Bootstrap the catalog file against real upstream data**

`v1/models.json` does not exist yet, so this first run bootstraps it. `SKIP_COMMIT` keeps it a local write.

```bash
touch .nojekyll
SKIP_COMMIT=1 go run ./cmd/sync
```

Expected: a log line like `updated: NN models (was 0)`, and `v1/models.json` now exists.

- [ ] **Step 7: Verify the bootstrapped catalog against the app's current table**

Every model in `Sources/Cost/Pricing.swift` should appear, with matching rates. Check a representative sample:

```bash
python3 -c "
import json
d = json.load(open('v1/models.json'))
print('models:', len(d['models']))
for m in ['claude-opus-4-8','claude-sonnet-5','gpt-5.6','gpt-5-pro','gpt-5.6-luna']:
    print(m, d['models'].get(m))
"
```

Expected: `claude-opus-4-8` at 5/25/6.25/0.5, `gpt-5.6` with `cacheCreationPerMillion` 6.25 (the override), `gpt-5-pro` with `cacheReadPerMillion` 0, and `gpt-5.6-luna` present from overrides alone. If a model from `Pricing.swift` is missing, add it to `overrides.json` and re-run.

- [ ] **Step 8: Verify the no-change path**

```bash
SKIP_COMMIT=1 go run ./cmd/sync
```

Expected: `no change (NN models)` and `v1/models.json` untouched (`git status --short` shows nothing for it).

- [ ] **Step 9: Commit**

```bash
git add .nojekyll v1/models.json internal/catalog/encode.go internal/catalog/encode_test.go cmd/sync/main.go
git commit -m "feat: add sync command and bootstrap the published catalog"
```

---

### Task 6: Container image, CI, and k3s manifests

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`
- Create: `.github/workflows/build.yml`
- Create: `k8s/namespace.yaml`
- Create: `k8s/cronjob.yaml`
- Create: `k8s/secret.example.yaml`
- Create: `README.md`

**Interfaces:**
- Consumes: `cmd/sync` from Task 5.
- Produces: image `ghcr.io/ericjypark/codex-island-model-catalog:<sha>`; CronJob `model-catalog-sync` in namespace `codexisland`.

- [ ] **Step 1: Write the Dockerfile**

Create `Dockerfile`:

```dockerfile
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/sync ./cmd/sync

FROM alpine:3.22
RUN apk add --no-cache git ca-certificates
COPY --from=build /out/sync /usr/local/bin/sync
ENTRYPOINT ["/usr/local/bin/sync"]
```

`git` is in the runtime image because the sync command shells out to it to clone, commit, and push.

Create `.dockerignore`:

```
.git
.superpowers
README.md
k8s/secret*.yaml
!k8s/secret.example.yaml
```

`k8s/` stays copyable — Step 3 adds an entrypoint script that lives there — but
`k8s/secret.yaml` must not be. `Dockerfile`'s `COPY . .` would otherwise sweep
the live PAT the repo instructs you to create there into the build-stage layer
and the local BuildKit cache. It never reaches CI (the file is gitignored, so a
CI checkout has no copy) or the published image (the final stage copies only
the binary), but a credential in a build cache is still a credential at rest.

- [ ] **Step 2: Build the image locally to verify it compiles**

Run: `docker build -t codex-island-model-catalog:dev .`

Expected: build succeeds, final image under ~30MB (`docker images codex-island-model-catalog:dev`).

- [ ] **Step 3: Write the entrypoint wrapper that clones before syncing**

The CronJob starts from an empty filesystem, so it must clone first. Create `k8s/entrypoint.sh` and add it to the image.

Append to `Dockerfile` before the `ENTRYPOINT` line:

```dockerfile
COPY --chmod=0755 k8s/entrypoint.sh /usr/local/bin/entrypoint.sh
```

and change the last line to:

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

Create `k8s/entrypoint.sh`:

```sh
#!/bin/sh
# Clone with the token in the remote URL, sync, then let the sync binary
# commit and push. set -u is deliberate: an unset token must fail loudly
# rather than produce an anonymous clone that cannot push.
set -eu

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
REPO_DIR=/tmp/repo
rm -rf "$REPO_DIR"

git clone --depth 1 \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/ericjypark/codex-island-model-catalog.git" \
  "$REPO_DIR"

REPO_DIR="$REPO_DIR" exec /usr/local/bin/sync
```

- [ ] **Step 4: Rebuild and smoke-test the image without a token**

Run: `docker build -t codex-island-model-catalog:dev . && docker run --rm codex-island-model-catalog:dev`

Expected: exits non-zero with `GITHUB_TOKEN is required`. That is the correct failure — it proves the guard works.

- [ ] **Step 5: Write the CI workflow**

Create `.github/workflows/build.yml`:

```yaml
name: build

on:
  push:
    branches: [main]
  pull_request:

# The default is whatever the repo is configured for, which on a public repo
# may be write-all. The image job widens this for itself; nothing else needs to.
permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.26"
      - run: go vet ./...
      - run: go test ./... -v

  image:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/arm64
          push: true
          tags: ghcr.io/ericjypark/codex-island-model-catalog:${{ github.sha }}
```

Only `linux/arm64` is built — the Pi is the sole consumer.

- [ ] **Step 6: Write the k3s manifests**

Create `k8s/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: codexisland
```

Create `k8s/secret.example.yaml`:

```yaml
# Copy to secret.yaml, fill in the token, apply, and do NOT commit it.
# The token is a fine-grained PAT with contents:write scoped to
# ericjypark/codex-island-model-catalog only.
apiVersion: v1
kind: Secret
metadata:
  name: codexisland-git
  namespace: codexisland
type: Opaque
stringData:
  GITHUB_TOKEN: github_pat_REPLACE_ME
```

Create `k8s/cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: model-catalog-sync
  namespace: codexisland
spec:
  schedule: "17 */6 * * *"
  concurrencyPolicy: Forbid
  # Unset, the controller counts missed schedules from lastScheduleTime and
  # permanently stops scheduling past 100 — 25 days of Pi downtime at this
  # interval, after which the CronJob silently never fires again. The trade:
  # a tick missed by more than an hour is now skipped rather than run late,
  # which is right for a job that is idempotent and runs again in six hours.
  startingDeadlineSeconds: 3600
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      # A run that hangs rather than fails would block every later run forever
      # under Forbid. git has no default network timeout, so a stalled clone
      # waits on TCP keepalive — over two hours on Linux defaults.
      activeDeadlineSeconds: 900
      # restartPolicy: Never retains a pod per failed attempt, and a retained
      # pod keeps its container snapshot — including /tmp/repo/.git/config,
      # which holds the PAT interpolated into the remote URL. A day is enough
      # to debug four six-hourly runs; weeks of a credential at rest is not
      # a trade worth making for logs nobody will read that late.
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          # Never, not OnFailure: OnFailure restarts in place and all three
          # attempts share one container-log slot, so the first two are lost.
          # This job is unattended and logs are its only failure signal.
          restartPolicy: Never
          containers:
            - name: sync
              image: ghcr.io/ericjypark/codex-island-model-catalog:REPLACE_WITH_SHA
              envFrom:
                - secretRef:
                    name: codexisland-git
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  cpu: 500m
                  # litellm.Fetch buffers up to 32 MiB and json.Unmarshal's it
                  # with the raw bytes still live, so 128Mi would OOMKill
                  # before the code's own ceiling ever tripped. Today's
                  # upstream file is a few MB; this makes the guard in the
                  # code the real limit rather than the manifest.
                  memory: 256Mi
```

`17 */6 * * *` rather than `0 */6 * * *` — an off-the-hour minute avoids piling onto the same upstream-fetch spike as every other cron on the internet.

- [ ] **Step 7: Add `secret.yaml` to gitignore**

Create `.gitignore`:

```
k8s/secret*.yaml
!k8s/secret.example.yaml
.superpowers/
```

The glob rather than the exact name: `secret.example.yaml` tells you to copy it,
and a maintainer who lands on `secret-prod.yaml` should still be covered.

`.superpowers/` holds scratch review artifacts. It is untracked either way, but
this repo is about to be public and `git add -A` should not be able to sweep it in.

- [ ] **Step 8: Write the README**

Create `README.md`:

```markdown
# codex-island-model-catalog

Model prices for [CodexIsland](https://github.com/ericjypark/codex-island),
published as a plain JSON file so new models do not require an app release.

**Endpoint:** https://ericjypark.github.io/codex-island-model-catalog/v1/models.json

## How it works

A bot polls [LiteLLM's price table][litellm] every six hours, keeps the
models CodexIsland tracks, converts per-token prices to per-million,
applies `overrides.json`, and runs a sanity gate before committing
`v1/models.json`. It commits only when prices actually change.

[litellm]: https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json

## Correcting a price

Prices are public and reviewable. If a value here is wrong, open a PR
against `overrides.json` — an override beats whatever upstream says:

```json
{ "gpt-5.6": { "cacheCreationPerMillion": 6.25 } }
```

Only the fields you list are replaced.

## Sanity gate

The bot refuses to publish data that looks broken:

- the run aborts if the model count drops below half of what is published
- a negative rate, or an input rate above $1000/M, is rejected
- a rate that moves by 10x or more is rejected
- a rejected model keeps its previously published value rather than
  vanishing, because a missing model prices to $0 in the app
- models are never removed, even if upstream drops them

## Development

```sh
go test ./...
SKIP_COMMIT=1 go run ./cmd/sync   # dry run against the local checkout
```
```

- [ ] **Step 9: Commit**

```bash
git add Dockerfile .dockerignore .gitignore README.md .github/workflows/build.yml k8s/
git commit -m "chore: add container build, CI, and k3s manifests"
```

---

### Task 7: Publish and deploy

The manual, out-of-band steps. Everything before this was local.

**Files:**
- Modify: `k8s/cronjob.yaml` (pin the real image SHA)

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: a live URL the companion app plan consumes.

- [ ] **Step 1: Push the private infra repo**

```bash
cd ~/Desktop/Projects/codex-island-infra && git push -u origin main
```

- [ ] **Step 2: Push the catalog repo and make it public**

```bash
cd ~/Desktop/Projects/codex-island-model-catalog && git push -u origin main
```

```bash
gh repo edit ericjypark/codex-island-model-catalog --visibility public --accept-visibility-change-consequences
```

- [ ] **Step 3: Verify CI built and pushed the image**

CI lives in the infra repo, and so does the image.

```bash
gh run watch --exit-status -R ericjypark/codex-island-infra
```

```bash
gh api /users/ericjypark/packages/container/codex-island-infra/versions --jq '.[0].metadata.container.tags'
```

Expected: the workflow succeeds and the package lists the head commit SHA as a tag.

- [ ] **Step 4: Enable GitHub Pages on the catalog repo**

```bash
gh api -X POST repos/ericjypark/codex-island-model-catalog/pages \
  -f 'source[branch]=main' -f 'source[path]=/'
```

Wait ~1 minute for the first Pages build, then verify:

```bash
curl -sS -D- -o /dev/null https://ericjypark.github.io/codex-island-model-catalog/v1/models.json
```

Expected: `HTTP/2 200` and an `etag:` header.

- [ ] **Step 4: Verify conditional GET returns 304**

```bash
ETAG=$(curl -sSI https://ericjypark.github.io/codex-island-model-catalog/v1/models.json | awk '/^etag:/{print $2}' | tr -d '\r')
curl -sS -o /dev/null -w '%{http_code}\n' -H "If-None-Match: $ETAG" https://ericjypark.github.io/codex-island-model-catalog/v1/models.json
```

Expected: `304`. The app's daily refresh depends on this.

- [ ] **Step 6: Mint the PAT and create the secret**

**The maintainer does this step, not an agent.** Create a fine-grained PAT at
https://github.com/settings/personal-access-tokens/new with **Repository
access:** only `ericjypark/codex-island-model-catalog` (the data repo — the bot
never writes to the infra repo), **Permissions:** Contents → Read and write.

Then, from `~/Desktop/Projects/codex-island-infra`:

```bash
cp k8s/secret.example.yaml k8s/secret.yaml
```

Paste the token into that copy, then pipe it over stdin rather than copying it
to the Pi — this way the token never lands on that filesystem at all, so there
is no `rm` to forget:

```bash
cat k8s/namespace.yaml | ssh ericpark@ericpark 'sudo k3s kubectl apply -f -' && cat k8s/secret.yaml | ssh ericpark@ericpark 'sudo k3s kubectl apply -f -'
```

- [ ] **Step 7: Pin the image SHA and deploy the CronJob**

The SHA is the infra repo's head, since that is what CI built the image from.

```bash
cd ~/Desktop/Projects/codex-island-infra && sed -i '' "s|REPLACE_WITH_SHA|$(git rev-parse HEAD)|" k8s/cronjob.yaml
```

```bash
scp k8s/cronjob.yaml ericpark@ericpark:/tmp/ && ssh ericpark@ericpark 'sudo k3s kubectl apply -f /tmp/cronjob.yaml'
```

- [ ] **Step 8: Trigger a manual run and verify it succeeds**

```bash
ssh ericpark@ericpark 'sudo k3s kubectl -n codexisland create job --from=cronjob/model-catalog-sync manual-1'
```

```bash
sleep 60 && ssh ericpark@ericpark 'sudo k3s kubectl -n codexisland logs job/manual-1'
```

Expected: `no change (78 models)` — the catalog was bootstrapped in Task 5 and pushed in Step 2, so a healthy run finds nothing to do. Any other outcome means the clone, the token, or the gate is misconfigured. `restartPolicy: Never` means each failed attempt is its own pod, so `kubectl -n codexisland get pods` lists them all if you need to read more than one.

Clean up:

```bash
ssh ericpark@ericpark 'sudo k3s kubectl -n codexisland delete job manual-1'
```

- [ ] **Step 9: Commit the pinned manifest**

```bash
cd ~/Desktop/Projects/codex-island-infra && git commit -qam "chore: pin sync image to released sha" && git push
```

---

## Done when

- `https://ericjypark.github.io/codex-island-model-catalog/v1/models.json` returns 200 with an ETag, and 304 on conditional GET.
- Every model in `Sources/Cost/Pricing.swift` appears in the payload with matching rates.
- `go test ./...` passes in the infra repo.
- A manual CronJob run completes and reports `no change`.
- The public catalog repo contains only `v1/models.json`, `overrides.json`, `config.json`, `.nojekyll`, `README.md`, `.gitignore` — no deployment shape.
- `k8s/secret.yaml` is untracked; no token appears anywhere in either repo's history.
