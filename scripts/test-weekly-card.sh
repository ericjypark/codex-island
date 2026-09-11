#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CARD_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$CARD_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$CARD_TEST_DIR/weekly-card-tests" \
  Sources/Model/IslandProvider.swift \
  Sources/Cost/TokenEvent.swift Sources/Cost/CostUsage.swift \
  Sources/Cost/CostBucketing.swift Sources/Cost/HistoricalUsageDay.swift Sources/Cost/CostSummary.swift \
  Sources/Cost/PricingCatalog.swift Sources/Cost/Pricing.swift \
  Sources/Sharing/WeeklyUsageSnapshot.swift Sources/Sharing/WeeklyCardTier.swift Sources/Sharing/WeeklyCardLaunchGate.swift \
  Tests/WeeklyUsageSnapshotTests.swift
"$CARD_TEST_DIR/weekly-card-tests"
