#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
history_snapshot="$1"
python3 - "$history_snapshot" <<'PY'
from pathlib import Path
import hashlib, json, sys
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text())
for path,digest in manifest['sourceCodeSha256'].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest, f'Mac reference source changed: {path}'
PY
history_sources=()
while IFS= read -r path; do history_sources+=("$path"); done < <(rg --files Sources -g '*.swift' | sort | rg -v '^Sources/App.swift$')
swiftc -Onone -target "$(uname -m)-apple-macos13.0" -parse-as-library -F Vendor/Sparkle \
  -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Sparkle \
  -Xlinker -rpath -Xlinker "$PWD/Vendor/Sparkle" \
  -o "$PWD/windows/artifacts/MacHistoryReference" "${history_sources[@]}" windows/reference/MacHistoryReference.swift
TZ=America/Chicago "$PWD/windows/artifacts/MacHistoryReference" "$history_snapshot"
