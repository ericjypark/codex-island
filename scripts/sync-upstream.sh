#!/bin/bash
# Merge the latest upstream release into the current customization branch.
# This script never resets or overwrites local history. It requires a clean
# worktree, creates a backup branch, and pauses safely when conflicts occur.

set -euo pipefail

cd "$(dirname "$0")/.."

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-origin}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
ACTION="${1:-sync}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sync-upstream.sh             Fetch, test, and merge upstream/main
  ./scripts/sync-upstream.sh --continue  Continue after resolving conflicts
  ./scripts/sync-upstream.sh --abort     Abort the current upstream merge

Optional environment variables:
  UPSTREAM_REMOTE=origin
  UPSTREAM_BRANCH=main
  SYNC_SKIP_TESTS=1
  SYNC_BUILD_APP=1
  SYNC_SDKROOT=/path/to/MacOSX.sdk
EOF
}

run_validation() {
  if [[ "${SYNC_SKIP_TESTS:-0}" != "1" ]]; then
    echo "Running tests..."
    local sdk="${SYNC_SDKROOT:-}"
    if [[ -z "$sdk" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]]; then
      sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    fi
    if [[ -n "$sdk" ]]; then
      SDKROOT="$sdk" \
        CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-island-module-cache" \
        ./scripts/run-tests.sh
    else
      CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-island-module-cache" \
        ./scripts/run-tests.sh
    fi
  fi

  if [[ "${SYNC_BUILD_APP:-0}" == "1" ]]; then
    echo "Building CodexIsland..."
    ./build.sh
  fi
}

case "$ACTION" in
  --help|-h)
    usage
    exit 0
    ;;
  --abort)
    if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
      git merge --abort
      echo "Upstream merge aborted; the pre-sync branch is still available."
    else
      echo "error: no upstream merge is in progress" >&2
      exit 1
    fi
    exit 0
    ;;
  --continue)
    if ! git rev-parse -q --verify MERGE_HEAD >/dev/null; then
      echo "error: no upstream merge is in progress" >&2
      exit 1
    fi
    if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
      echo "error: unresolved conflicts remain" >&2
      git diff --name-only --diff-filter=U >&2
      exit 1
    fi
    run_validation
    git commit --no-edit
    echo "Upstream merge completed successfully."
    exit 0
    ;;
  sync)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "error: a merge is already in progress; use --continue or --abort" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: commit or stash local changes before syncing" >&2
  exit 1
fi

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$current_branch" ]]; then
  echo "error: switch to your customization branch before syncing" >&2
  exit 1
fi

echo "Fetching ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}..."
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" --tags
target="${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

if git merge-base --is-ancestor "$target" HEAD; then
  echo "Already up to date with ${target}."
  run_validation
  exit 0
fi

stamp="$(date +%Y%m%d-%H%M%S)"
short_head="$(git rev-parse --short HEAD)"
backup_branch="codex/backup-before-upstream-${stamp}-${short_head}"
git branch "$backup_branch" HEAD
echo "Backup created: ${backup_branch}"

if ! git merge --no-ff --no-commit "$target"; then
  cat >&2 <<EOF

The merge paused because conflicts need review. Your local work is safe.
Resolve the listed files, stage them with git add, then run:
  ./scripts/sync-upstream.sh --continue

To restore the pre-merge state, run:
  ./scripts/sync-upstream.sh --abort

Backup branch: ${backup_branch}
EOF
  exit 1
fi

if ! run_validation; then
  cat >&2 <<EOF

Validation failed, so the merge has not been committed.
Fix the issue and run ./scripts/sync-upstream.sh --continue,
or run ./scripts/sync-upstream.sh --abort.
Backup branch: ${backup_branch}
EOF
  exit 1
fi

git commit --no-edit
echo "Merged ${target} into ${current_branch}."
echo "Backup branch: ${backup_branch}"
