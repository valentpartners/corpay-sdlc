#!/usr/bin/env bash
# AISDLC worktree cleanup — removes per-story worktrees + local branches
# for every story currently in `state: done` in the manifest. Safe to run
# mid-feature; only acts on done stories, leaves the rest alone.
#
# Usage:
#   bash scripts/cleanup-worktrees.sh                  # auto-detect manifest by current branch
#   bash scripts/cleanup-worktrees.sh --feature SLUG   # specify by feature-slug
#   bash scripts/cleanup-worktrees.sh --dry-run        # report only, don't remove

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AISDLC_JSON="$REPO_ROOT/.claude/aisdlc.json"

FEATURE_SLUG=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --feature) shift; FEATURE_SLUG="${1:-}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[$(date -u +%H:%M:%SZ)] $*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

for tool in git yq; do
  command -v "$tool" >/dev/null || fail "$tool required on PATH"
done

[ -f "$AISDLC_JSON" ] || fail "missing $AISDLC_JSON"
cd "$REPO_ROOT" || fail "cannot cd $REPO_ROOT"

BRANCH_PREFIX=$(jq -r '.branches.prefix' "$AISDLC_JSON")
PATH_MANIFEST_TPL=$(jq -r '.paths.manifest' "$AISDLC_JSON")
PATH_WORKTREES_TPL=$(jq -r '.paths.worktrees' "$AISDLC_JSON")

expand_path() {
  local t="$1" slug="$2" sid="${3:-}"
  t="${t//\{feature-slug\}/$slug}"
  t="${t//\{story-id\}/$sid}"
  echo "${t%/}"
}

# --- locate manifest --------------------------------------------------------

MANIFEST=""
if [ -n "$FEATURE_SLUG" ]; then
  MANIFEST="$REPO_ROOT/$(expand_path "$PATH_MANIFEST_TPL" "$FEATURE_SLUG")"
  [ -f "$MANIFEST" ] || fail "no manifest at $MANIFEST"
else
  current_branch=$(git branch --show-current)
  [ -n "$current_branch" ] || fail "could not determine current branch; pass --feature SLUG"
  MANIFEST_GLOB="$REPO_ROOT/${PATH_MANIFEST_TPL//\{feature-slug\}/*}"
  for candidate in $MANIFEST_GLOB; do
    [ -f "$candidate" ] || continue
    branch=$(yq '.feature.branch' "$candidate")
    if [ "$branch" = "$current_branch" ]; then
      if [ -n "$MANIFEST" ]; then
        fail "multiple manifests match branch '$current_branch': $MANIFEST and $candidate"
      fi
      MANIFEST="$candidate"
    fi
  done
  [ -n "$MANIFEST" ] || fail "no manifest matches current branch '$current_branch'; pass --feature SLUG"
  FEATURE_SLUG=$(yq '.feature.slug' "$MANIFEST")
fi

log "feature=$FEATURE_SLUG manifest=$MANIFEST dry-run=$DRY_RUN"

# --- iterate stories --------------------------------------------------------

cleaned=0
skipped_state=0
skipped_missing=0
declare -a SKIPPED_DETAIL

while IFS=$'\t' read -r sid state; do
  [ -z "$sid" ] && continue
  branch="${BRANCH_PREFIX}${sid}"
  wt=$(expand_path "$PATH_WORKTREES_TPL" "$FEATURE_SLUG" "$sid")

  if [ "$state" != "done" ]; then
    skipped_state=$((skipped_state + 1))
    SKIPPED_DETAIL+=("$sid: state=$state")
    continue
  fi

  wt_present=0
  br_present=0
  [ -d "$REPO_ROOT/$wt" ] && wt_present=1
  git show-ref --verify --quiet "refs/heads/$branch" && br_present=1

  if [ "$wt_present" = 0 ] && [ "$br_present" = 0 ]; then
    skipped_missing=$((skipped_missing + 1))
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "would clean: $sid (worktree=$wt_present branch=$br_present)"
    cleaned=$((cleaned + 1))
    continue
  fi

  if [ "$wt_present" = 1 ]; then
    git worktree remove "$wt" --force 2>/dev/null \
      || { log "  warn: failed to remove worktree $wt"; }
  fi
  if [ "$br_present" = 1 ]; then
    git branch -D "$branch" 2>/dev/null \
      || { log "  warn: failed to delete branch $branch"; }
  fi
  log "cleaned: $sid (worktree + branch)"
  cleaned=$((cleaned + 1))
done < <(yq -r '.stories[] | [.id, .state] | @tsv' "$MANIFEST")

# --- summary ----------------------------------------------------------------

echo "" >&2
log "summary: cleaned=$cleaned skipped_state=$skipped_state skipped_missing=$skipped_missing"
if [ "$skipped_state" -gt 0 ]; then
  log "stories not yet done (left intact):"
  for line in "${SKIPPED_DETAIL[@]}"; do
    log "  - $line"
  done
fi
log "feature integration branch ($(yq '.feature.branch' "$MANIFEST")) left alone — delete it manually after merging into protected."
