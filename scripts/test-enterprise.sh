#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/setup-sparkle.sh
OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT
swiftc -parse-as-library -F Vendor/Sparkle -framework Sparkle \
  -Xlinker -rpath -Xlinker "$PWD/Vendor/Sparkle" \
  -o "$OUT_DIR/enterprise-tests" \
  $(find Sources -name '*.swift' ! -path 'Sources/App.swift' | sort) \
  Tests/EnterpriseUsageTests.swift
"$OUT_DIR/enterprise-tests"
