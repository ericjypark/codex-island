#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHART_QA_DIR="$PWD/notes/chart-integration-20260929"
CHART_QA_APP="$CHART_QA_DIR/ChartQA.app"
mkdir -p "$CHART_QA_APP/Contents/MacOS" "$CHART_QA_APP/Contents/Resources" "$CHART_QA_APP/Contents/Frameworks"
./scripts/setup-sparkle.sh
cp Resources/*_logo.* "$CHART_QA_APP/Contents/Resources/"
cp -R Resources/*.lproj "$CHART_QA_APP/Contents/Resources/"
cp -a Vendor/Sparkle/Sparkle.framework "$CHART_QA_APP/Contents/Frameworks/"
cat > "$CHART_QA_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChartQA</string>
<key>CFBundleIdentifier</key><string>dev.codexisland.ChartQA</string>
<key>CFBundleName</key><string>ChartQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
CHART_QA_SOURCES=()
while IFS= read -r file; do CHART_QA_SOURCES+=("$file"); done < <(find Sources -name '*.swift' ! -name 'App.swift' | sort)
swiftc -target "$(uname -m)-apple-macos13.0" -parse-as-library -F Vendor/Sparkle \
  -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Sparkle \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  -o "$CHART_QA_APP/Contents/MacOS/ChartQA" \
  "${CHART_QA_SOURCES[@]}" Tests/QuotaChartRenderHarness.swift
CODEXISLAND_DEMO=1 "$CHART_QA_APP/Contents/MacOS/ChartQA" "${1:-$CHART_QA_DIR/renders}"
