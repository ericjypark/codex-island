#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLINE_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$SPARKLINE_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$SPARKLINE_TEST_DIR/sparkline-tests" \
  Sources/Views/Charts/SparklinePath.swift Tests/SparklinePathTests.swift
"$SPARKLINE_TEST_DIR/sparkline-tests"
