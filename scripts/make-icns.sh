#!/bin/bash
# Regenerate Resources/CodexIsland.icns + Resources/codexisland_logo.png from
# the canonical Assets/ source files. Run after editing any of:
#   - Assets/codexisland-app-icon-light.png  (the in-Dock icon, default source)
#   - Assets/codexisland-app-icon-dark.png   (alternate; SOURCE= override)
#   - Assets/codexisland-logo.png            (the brand glyph used in Settings)
#
# Override: SOURCE=Assets/codexisland-app-icon-dark.png ./scripts/make-icns.sh

set -euo pipefail
cd "$(dirname "$0")/.."

ICON_SOURCE="${SOURCE:-Assets/codexisland-app-icon-light.png}"
GLYPH_SOURCE="Assets/codexisland-logo.png"
ICNS_OUT="Resources/CodexIsland.icns"
GLYPH_OUT="Resources/codexisland_logo.png"

for f in "$ICON_SOURCE" "$GLYPH_SOURCE"; do
  if [[ ! -f "$f" ]]; then
    echo "error: source missing: $f" >&2
    exit 1
  fi
done

TMP=$(mktemp -d)
ICONSET="$TMP/CodexIsland.iconset"
mkdir "$ICONSET"

# Ten sizes the macOS HIG asks for. iconutil bundles them into a single .icns.
sips -z 16   16   "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
rm -rf "$TMP"

cp "$GLYPH_SOURCE" "$GLYPH_OUT"

echo "✓ $ICNS_OUT  ←  $ICON_SOURCE  ($(du -h "$ICNS_OUT" | cut -f1))"
echo "✓ $GLYPH_OUT  ←  $GLYPH_SOURCE  ($(du -h "$GLYPH_OUT" | cut -f1))"
