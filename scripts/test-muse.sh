#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MUSE_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$MUSE_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$MUSE_TEST_DIR/muse-tests" \
  Sources/Model/IslandProvider.swift \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/ConnectedUsage.swift \
  Sources/Usage/GrokConnection.swift \
  Sources/Usage/MuseConnection.swift \
  Tests/MuseConnectionTests.swift
"$MUSE_TEST_DIR/muse-tests"
