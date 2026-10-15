#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHART_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$CHART_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$CHART_TEST_DIR/chart-tests" \
  Sources/Model/ChartStyle.swift Sources/Model/StylePreferenceStore.swift \
  Sources/Model/AppEnvironment.swift Sources/Model/AppLanguageStore.swift \
  Sources/Localization/L10n.swift Tests/ChartStyleTests.swift
"$CHART_TEST_DIR/chart-tests"
