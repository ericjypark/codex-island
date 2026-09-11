#!/bin/bash
set -euo pipefail

RECOVERY_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "${CODEXISLAND_APP:-}" ]]; then
  RECOVERY_APPS=("$CODEXISLAND_APP")
else
  RECOVERY_APPS=(
    "$RECOVERY_SCRIPT_DIR/../.."
    "$RECOVERY_SCRIPT_DIR/../build/CodexIsland.app"
    "/Applications/CodexIsland.app"
    "$HOME/Applications/CodexIsland.app"
  )
fi

for RECOVERY_APP in "${RECOVERY_APPS[@]}"; do
  if [[ -x "$RECOVERY_APP/Contents/MacOS/CodexIsland" && -f "$RECOVERY_APP/Contents/Resources/recover-claude-usage.sh" ]]; then
    exec "$RECOVERY_APP/Contents/MacOS/CodexIsland" --recover-claude "$@"
  fi
done

echo "Install a CodexIsland version with usage recovery, then run this script again." >&2
echo "For a custom app location, set CODEXISLAND_APP to its .app path." >&2
exit 1
