#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
performance_app="$PWD/windows/artifacts/MacPerformance.app"
mkdir -p "$performance_app/Contents/MacOS" "$performance_app/Contents/Resources"
cp Resources/*_logo.* "$performance_app/Contents/Resources/"
cp -R Resources/*.lproj "$performance_app/Contents/Resources/"
cat > "$performance_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.codexisland.WindowsPerformanceReference</string>
<key>CFBundleExecutable</key><string>MacPerformance</string>
<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - <<'PY'
from pathlib import Path
source=Path('Sources/Views/IslandRootView.swift').read_text()
anchor='    @Environment(\\.accessibilityReduceTransparency) private var reduceTransparency'
assert source.count(anchor)==1
initializer='''    init(model: IslandModel, benchmarkHovering: Bool = false, benchmarkVisible: Bool = false, benchmarkPills: Bool = false) {
        self.model = model
        self._hovering = State(initialValue: benchmarkHovering)
        self._contentVisible = State(initialValue: benchmarkVisible)
        self._pillsVisible = State(initialValue: benchmarkPills)
    }

'''
Path('windows/artifacts/PerformanceRootView.swift').write_text(source.replace(anchor,initializer+anchor))
PY
performance_sources=()
while IFS= read -r path; do
 if [[ "$path" == "Sources/Views/IslandRootView.swift" ]]; then
  performance_sources+=("windows/artifacts/PerformanceRootView.swift")
 else performance_sources+=("$path"); fi
done < <(rg --files Sources -g '*.swift' | sort | rg -v '^Sources/App.swift$')
swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macos13.0" -parse-as-library -F Vendor/Sparkle \
 -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Sparkle \
 -Xlinker -rpath -Xlinker "$PWD/Vendor/Sparkle" \
 -o "$performance_app/Contents/MacOS/MacPerformance" "${performance_sources[@]}" windows/reference/PerformanceMac.swift
CODEXISLAND_DEMO=1 "$performance_app/Contents/MacOS/MacPerformance" "$PWD/windows/artifacts"
