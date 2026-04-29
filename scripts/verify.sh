#!/bin/bash
# Build and smoke-launch the app for 1 second, then kill it.
# Used after every commit to confirm the binary launches without crashing.
# (CodexIsland is a forever-running background overlay, so we can't just `./binary`.)

set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

BIN="./build/CodexIsland.app/Contents/MacOS/CodexIsland"
"$BIN" >/dev/null 2>&1 &
PID=$!
sleep 1
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    echo "✓ launched cleanly"
else
    wait "$PID" 2>/dev/null || true
    echo "✗ binary exited before 1s — likely a crash"
    exit 1
fi
