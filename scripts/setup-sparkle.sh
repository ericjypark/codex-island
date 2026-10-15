#!/bin/bash
# Downloads and unpacks the Sparkle framework + tools into Vendor/Sparkle.
# Reuses only an extraction that completed for the requested version.

set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.1"
DEST="Vendor/Sparkle"
LOCK_DIR="${DEST}.lock"
MAX_ATTEMPTS=3
STAGING=""
LOCK_HELD=""
LOCK_WAIT_LIMIT=300

cleanup() {
  if [[ -n "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
  if [[ -n "$LOCK_HELD" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$DEST")"

lock_owner_alive() {
  local pid
  [[ -f "$LOCK_DIR/pid" ]] || return 0
  pid=$(cat "$LOCK_DIR/pid" 2>/dev/null) || return 0
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  kill -0 "$pid" 2>/dev/null
}

# Unknown owners may still be writing their pid. Only one waiter can reap
# a dead owner, so a second waiter cannot remove a newly acquired lock.
lock_waits=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  if (( lock_waits >= LOCK_WAIT_LIMIT )); then
    echo "error: timed out waiting for Sparkle setup lock at ${LOCK_DIR}; if no setup is running, remove that lock and retry" >&2
    exit 1
  fi
  if ! lock_owner_alive && mkdir "$LOCK_DIR/reaper" 2>/dev/null; then
    if ! lock_owner_alive; then
      rm -rf "$LOCK_DIR"
    else
      rmdir "$LOCK_DIR/reaper"
    fi
  else
    sleep 0.2
  fi
  lock_waits=$(( lock_waits + 1 ))
done
LOCK_HELD=1
echo "$$" > "$LOCK_DIR/pid"

# Restore a cache moved aside by an interrupted publish before discarding
# old backups, so a completed cache remains available offline.
for leftover in "${DEST}".bak.*; do
  [[ -e "$leftover" ]] || continue
  if [[ ! -e "$DEST" && -f "$leftover/Sparkle.framework/Sparkle" && -x "$leftover/bin/sign_update" ]]; then
    mv "$leftover" "$DEST"
  else
    rm -rf "$leftover"
  fi
done

framework_ok() {
  [[ -f "${DEST}/Sparkle.framework/Sparkle" && -x "${DEST}/bin/sign_update" ]]
}

if framework_ok; then
  if [[ -f "${DEST}/.version" ]] && [[ "$(cat "${DEST}/.version")" == "$SPARKLE_VERSION" ]]; then
    echo "Sparkle ${SPARKLE_VERSION} already vendored at ${DEST}"
    exit 0
  elif [[ ! -f "${DEST}/.version" ]]; then
    legacy_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "${DEST}/Sparkle.framework/Resources/Info.plist" 2>/dev/null || true)
    if [[ "$legacy_version" == "$SPARKLE_VERSION" ]]; then
      printf '%s\n' "$SPARKLE_VERSION" > "${DEST}/.version"
      echo "adopted existing Sparkle cache at ${DEST}"
      exit 0
    fi
  fi
fi

# A transient network failure should not fail the build outright: retry the
# download/extraction with backoff inside a single run. A failed attempt
# never touches the reusable cache.
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  if [[ -n "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
  STAGING=$(mktemp -d "${DEST}.tmp.XXXXXX")
  TARBALL="$STAGING/Sparkle.tar.xz"
  echo "downloading Sparkle ${SPARKLE_VERSION} (attempt ${attempt}/${MAX_ATTEMPTS})..."
  if curl -fsSL -o "$TARBALL" \
      "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    && tar -xJf "$TARBALL" -C "$STAGING" \
    && [[ -f "$STAGING/Sparkle.framework/Sparkle" && -x "$STAGING/bin/sign_update" ]]; then
    break
  fi
  echo "warning: download/extraction failed (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
  if (( attempt < MAX_ATTEMPTS )); then
    sleep $(( 1 << (attempt - 1) ))
  fi
  attempt=$(( attempt + 1 ))
done
if (( attempt > MAX_ATTEMPTS )); then
  echo "error: failed to download and extract Sparkle ${SPARKLE_VERSION} after ${MAX_ATTEMPTS} attempts" >&2
  exit 1
fi
rm -f "$TARBALL"
printf '%s\n' "$SPARKLE_VERSION" > "$STAGING/.version"

# Move any existing cache aside, then rename the staged dir into place. The
# lock above keeps concurrent runs from interleaving here.
BACKUP="${DEST}.bak.$$"
if [[ -e "$DEST" ]]; then
  mv "$DEST" "$BACKUP"
fi
mv "$STAGING" "$DEST"
STAGING=""
rm -rf "$BACKUP"

echo "vendored Sparkle ${SPARKLE_VERSION} at ${DEST}"
