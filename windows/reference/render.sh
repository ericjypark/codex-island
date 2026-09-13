#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
reference_app="$PWD/windows/artifacts/MacReference.app"
mkdir -p "$reference_app/Contents/MacOS" "$reference_app/Contents/Resources" "$PWD/windows/artifacts/mac-reference"
cp Resources/*_logo.* "$reference_app/Contents/Resources/"
cp -R Resources/*.lproj "$reference_app/Contents/Resources/"
cat > "$reference_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.codexisland.WindowsParityReference</string>
<key>CFBundleExecutable</key><string>MacReference</string>
<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
reference_version=$(cat VERSION)
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $reference_version" "$reference_app/Contents/Info.plist"
python3 - <<'REFPY'
from pathlib import Path
source=Path('Sources/Views/OverviewView.swift').read_text()
old='@State private var selectedDate: Date?'
assert source.count(old)==1
source=source.replace(old,old+' = ProcessInfo.processInfo.environment["WINDOWS_REFERENCE_DAY"].flatMap { ISO8601DateFormatter().date(from: $0) }')
Path('windows/artifacts/ReferenceOverview.swift').write_text(source)
updater=Path('Sources/Update/UpdaterController.swift').read_text()
assert 'startingUpdater: true' in updater
Path('windows/artifacts/ReferenceUpdater.swift').write_text(updater.replace('startingUpdater: true','startingUpdater: false'))
REFPY
reference_sources=()
while IFS= read -r path; do if [[ "$path" == "Sources/Views/OverviewView.swift" ]]; then reference_sources+=("windows/artifacts/ReferenceOverview.swift"); elif [[ "$path" == "Sources/Update/UpdaterController.swift" ]]; then reference_sources+=("windows/artifacts/ReferenceUpdater.swift"); else reference_sources+=("$path"); fi; done < <(rg --files Sources -g '*.swift' | sort | rg -v '^Sources/App.swift$')
swiftc -Onone -target "$(uname -m)-apple-macos13.0" -parse-as-library -F Vendor/Sparkle \
 -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Sparkle \
 -Xlinker -rpath -Xlinker "$PWD/Vendor/Sparkle" \
 -o "$reference_app/Contents/MacOS/MacReference" "${reference_sources[@]}" windows/reference/RenderMacReference.swift
CODEXISLAND_DEMO=1 "$reference_app/Contents/MacOS/MacReference" "$PWD/windows/artifacts/mac-reference" "$@"
