#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
LEDGER_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$LEDGER_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$LEDGER_TEST_DIR/usage-ledger-tests" \
  Sources/Cost/TokenEvent.swift Sources/Cost/UsageLedger.swift \
  Sources/Cost/GrokLogReader.swift Sources/Cost/LocalCostScan.swift Sources/Cost/LogParseCache.swift \
  Sources/Cost/ClaudeLogReader.swift Sources/Cost/CodexLogReader.swift \
  Sources/Cost/CostUsage.swift Sources/Cost/CostBucketing.swift Sources/Cost/HistoricalUsageDay.swift Sources/Cost/CostSummary.swift \
  Sources/Cost/PricingCatalog.swift Sources/Cost/Pricing.swift \
  Tests/UsageLedgerTests.swift
"$LEDGER_TEST_DIR/usage-ledger-tests"
