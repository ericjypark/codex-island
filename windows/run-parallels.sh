#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
vm_name="${1:-Windows 11}"
prlctl exec "$vm_name" --current-user powershell -NoProfile -ExecutionPolicy Bypass -File \
  "$(printf '%s' "$project_dir/run.ps1" | sed "s|^$HOME|\\\\\\\\Mac\\\\Home|; s|/|\\\\|g")"
