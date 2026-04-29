#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="CodexIsland"
BUNDLE_ID="dev.codexisland.CodexIsland"
VERSION="$(cat VERSION)"
BUILD_DIR="./build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp ./Resources/claude_logo.png "$RES_DIR/claude_logo.png"
cp ./Resources/openai_logo.png "$RES_DIR/openai_logo.png"

SWIFT_SOURCES=$(find Sources -name '*.swift' | sort)

swiftc \
  -target arm64-apple-macos26.0 \
  -O \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS_DIR/$APP_NAME" \
  $SWIFT_SOURCES

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>CodexIsland</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Eric Park. MIT licensed.</string>
</dict>
</plist>
EOF

echo "✓ built $APP_DIR ($VERSION)"
