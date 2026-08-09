#!/bin/bash
# Compiles the usage-resolution sources together with the test harness and
# runs it. No XCTest/SPM — mirrors build.sh's bare-swiftc approach. The env
# token stub routes resolveUsage through the injected probe deterministically
# (see Tests/ResolveUsageTests.swift).
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/resolve-usage-tests" \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/ClaudeCredentials.swift \
  Tests/ResolveUsageTests.swift

CLAUDE_CODE_OAUTH_TOKEN="test-stub-token" "$OUT_DIR/resolve-usage-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/notch-height-tests" \
  Sources/Model/NotchInfo.swift \
  Sources/Model/IslandSpacingStore.swift \
  Sources/Model/PreferenceStorage.swift \
  Tests/NotchHeightTests.swift

"$OUT_DIR/notch-height-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/codex-task-status-log-parser-tests" \
  Sources/Model/CodexTaskStatusLogParser.swift \
  Tests/CodexTaskStatusLogParserTests.swift

"$OUT_DIR/codex-task-status-log-parser-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/usage-merge-tests" \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Tests/UsageMergeTests.swift

"$OUT_DIR/usage-merge-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-catalog-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogTests.swift

"$OUT_DIR/pricing-catalog-tests"

swiftc \
  -parse-as-library \
  -sanitize=thread \
  -o "$OUT_DIR/pricing-catalog-race-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogRaceTests.swift

"$OUT_DIR/pricing-catalog-race-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingTests.swift

"$OUT_DIR/pricing-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-precedence-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingPrecedenceTests.swift

"$OUT_DIR/pricing-precedence-tests"
