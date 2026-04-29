#!/bin/bash
# Builds the .app and packages a DMG for distribution.
# Requires `brew install create-dmg`. Unsigned — no Apple Developer Program
# certificates involved. Ad-hoc codesign keeps Apple Silicon Macs from
# rejecting the binary as "damaged" after re-download.

set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
APP_NAME="CodexIsland"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/CodexIsland-$VERSION.dmg"

./build.sh

rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "build/$APP_NAME.app" "$DIST/"

# Ad-hoc sign — does NOT satisfy Gatekeeper, but prevents the
# "MacIsland is damaged and can't be opened" failure mode that
# unsigned Apple Silicon binaries hit after a download round-trip.
codesign --force --deep --sign - "$APP"

rm -f "$DMG"
create-dmg \
  --volname "CodexIsland $VERSION" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "$APP_NAME.app" 140 180 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "$DMG" \
  "$APP"

echo ""
echo "✓ $DMG"
echo "  size: $(du -h "$DMG" | cut -f1)"
echo "  sha256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
