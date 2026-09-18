#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
quota_snapshot="$1"
quota_app="$PWD/windows/artifacts/MacQuotaReference.app"
mkdir -p "$quota_app/Contents/MacOS"
cat > "$quota_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.codexisland.WindowsQuotaReference</string>
<key>CFBundleExecutable</key><string>MacQuotaReference</string>
<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - <<'PY'
from pathlib import Path
source=Path('Sources/Views/Charts/SparkChart.swift').read_text()
assert source.count('private struct SparkSVG: View')==1
Path('windows/artifacts/ReferenceSparkChart.swift').write_text(source.replace('private struct SparkSVG: View','struct SparkSVG: View'))
PY
quota_sources=()
while IFS= read -r path; do
  if [[ "$path" == "Sources/Views/Charts/SparkChart.swift" ]]; then quota_sources+=("windows/artifacts/ReferenceSparkChart.swift"); else quota_sources+=("$path"); fi
done < <(rg --files Sources -g '*.swift' | sort | rg -v '^Sources/App.swift$')
swiftc -Onone -target "$(uname -m)-apple-macos13.0" -parse-as-library -F Vendor/Sparkle \
  -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Sparkle \
  -Xlinker -rpath -Xlinker "$PWD/Vendor/Sparkle" \
  -o "$quota_app/Contents/MacOS/MacQuotaReference" "${quota_sources[@]}" windows/reference/MacQuotaReference.swift
CODEXISLAND_DEMO=0 "$quota_app/Contents/MacOS/MacQuotaReference" "$quota_snapshot"
