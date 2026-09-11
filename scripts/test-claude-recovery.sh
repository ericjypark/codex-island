#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RECOVERY_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$RECOVERY_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$RECOVERY_TEST_DIR/claude-recovery-tests" \
  Sources/Cost/TokenEvent.swift Sources/Cost/UsageLedger.swift \
  Sources/Cost/LogParseCache.swift Sources/Cost/ClaudeLogReader.swift \
  Sources/Cost/CostUsage.swift Sources/Cost/CostBucketing.swift Sources/Cost/HistoricalUsageDay.swift \
  Sources/Recovery/ClaudeUsageRecovery.swift Tests/ClaudeUsageRecoveryTests.swift
"$RECOVERY_TEST_DIR/claude-recovery-tests"

swiftc -parse-as-library -o "$RECOVERY_TEST_DIR/recovery-model-tests" \
  Sources/Cost/TokenEvent.swift Sources/Cost/UsageLedger.swift \
  Sources/Cost/LogParseCache.swift Sources/Cost/ClaudeLogReader.swift \
  Sources/Cost/CostUsage.swift Sources/Cost/CostBucketing.swift Sources/Cost/HistoricalUsageDay.swift \
  Sources/Recovery/ClaudeUsageRecovery.swift Sources/Recovery/ClaudeRecoveryModel.swift \
  Tests/ClaudeRecoveryModelTests.swift
"$RECOVERY_TEST_DIR/recovery-model-tests"
