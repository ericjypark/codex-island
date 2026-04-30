#!/bin/bash
# Builds the .app and packages a DMG for distribution.
# Requires `npm install --global create-dmg` (Node 20+). Unsigned — no Apple
# Developer Program certificates involved. Ad-hoc codesign keeps Apple Silicon
# Macs from rejecting the binary as "damaged" after re-download.
#
# Update flow: after the DMG is built, signs it with the Sparkle EdDSA key
# (private key stored in the user's Keychain by `bin/generate_keys`) and
# regenerates docs/appcast.xml. Commit + push appcast.xml to publish the
# update — Sparkle clients fetch it from main.

set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
APP_NAME="CodexIsland"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/CodexIsland-$VERSION.dmg"
CREATE_DMG_OUT="$DIST/CodexIsland $VERSION.dmg"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg is required. Install with: npm install --global create-dmg" >&2
  exit 1
fi

./build.sh

rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "build/$APP_NAME.app" "$DIST/"

# Ad-hoc sign — does NOT satisfy Gatekeeper, but prevents the
# "CodexIsland is damaged and can't be opened" failure mode that
# unsigned Apple Silicon binaries hit after a download round-trip.
codesign --force --deep --sign - "$APP"

rm -f "$DMG" "$CREATE_DMG_OUT"
create-dmg \
  --overwrite \
  --no-code-sign \
  --dmg-title "CodexIsland $VERSION" \
  "$APP" \
  "$DIST"

if [[ -f "$CREATE_DMG_OUT" ]]; then
  mv "$CREATE_DMG_OUT" "$DMG"
fi

DMG_SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
DMG_SIZE_BYTES="$(stat -f%z "$DMG")"

# Sign the DMG with Sparkle's EdDSA key, then write appcast.xml as a release
# asset. Two ways to provide the key:
#   - Local: stored in Keychain by `Vendor/Sparkle/bin/generate_keys` (default)
#   - CI:    file path in $SPARKLE_PRIVATE_KEY_PATH (passed via GitHub Secret)
SIGN_TOOL="Vendor/Sparkle/bin/sign_update"
APPCAST="$DIST/appcast.xml"

have_key=0
sign_args=()
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" && -f "${SPARKLE_PRIVATE_KEY_PATH}" ]]; then
  sign_args+=(--ed-key-file "${SPARKLE_PRIVATE_KEY_PATH}")
  have_key=1
elif security find-generic-password -s "https://sparkle-project.org" >/dev/null 2>&1; then
  have_key=1
fi

if [[ -x "$SIGN_TOOL" && $have_key -eq 1 ]]; then
  SIG_LINE="$("$SIGN_TOOL" ${sign_args[@]+"${sign_args[@]}"} "$DMG")"
  EDSIG="$(echo "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"

  RELEASE_URL="https://github.com/ericjypark/codex-island/releases/download/v${VERSION}/$(basename "$DMG")"
  PUBDATE="$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"

  cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>CodexIsland</title>
    <link>https://github.com/ericjypark/codex-island/releases/latest/download/appcast.xml</link>
    <description>Most recent CodexIsland release.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/ericjypark/codex-island/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="$RELEASE_URL" sparkle:version="$VERSION" sparkle:shortVersionString="$VERSION" length="$DMG_SIZE_BYTES" type="application/octet-stream" sparkle:edSignature="$EDSIG" />
    </item>
  </channel>
</rss>
EOF

  echo "✓ $APPCAST signed and ready to publish"
else
  echo "⚠ skipping appcast — sign_update missing or no signing key (see docs/SPARKLE.md)"
fi

echo ""
echo "✓ $DMG"
echo "  size: $(du -h "$DMG" | cut -f1)"
echo "  sha256: $DMG_SHA256"
