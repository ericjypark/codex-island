#!/bin/bash
# Downloads and unpacks the Sparkle framework + tools into Vendor/Sparkle.
# Idempotent: does nothing if Vendor/Sparkle/Sparkle.framework already exists.

set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.1"
DEST="Vendor/Sparkle"

if [[ -d "${DEST}/Sparkle.framework" ]]; then
  echo "Sparkle ${SPARKLE_VERSION} already vendored at ${DEST}"
  exit 0
fi

mkdir -p "$DEST"
TARBALL="$DEST/Sparkle.tar.xz"

echo "downloading Sparkle ${SPARKLE_VERSION}..."
curl -fsSL -o "$TARBALL" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

tar -xJf "$TARBALL" -C "$DEST"
rm "$TARBALL"

echo "vendored Sparkle ${SPARKLE_VERSION} at ${DEST}"
