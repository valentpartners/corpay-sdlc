#!/usr/bin/env bash
# AISDLC worktree cleanup — end-of-feature teardown before `to-qa-handoff`.
#
# Worktrees persist through `done` (the runner does NOT tear them down on
# merge) so that per-story `testing.md` and other runs/ artefacts survive
# until they can be aggregated. This script:
#
#   1. Refuses to run if any non-terminal story (anything other than `done`
#      or `wontfix`) still has a worktree — testing isn't complete yet.
#   2. For each `done` story: rsyncs the worktree's
#      docs/ai-runs/{slug}/{story-id}/ back into the integration tree
#      (gitignored — physically present, not committed), then removes the
#      worktree and local branch.
#   3. After clean exit, the human invokes `to-qa-handoff` to synthesize the
#      feature-level QA distribution doc.
#
# Usage:
#   bash scripts/cleanup-worktrees.sh                  # auto-detect manifest by current branch
#   bash scripts/cleanup-worktrees.sh --feature SLUG   # specify by feature-slug
#   bash scripts/cleanup-worktrees.sh --dry-run        # report only, don't remove or copy

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

for tool in git yq rsync jq; do
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

PATH_RUNS_TPL=$(jq -r '.paths.runs' "$AISDLC_JSON")

log "feature=$FEATURE_SLUG manifest=$MANIFEST dry-run=$DRY_RUN"

# --- pre-flight: refuse if any non-terminal story still has a worktree ------

declare -a BAIL_LIST
while IFS=$'\t' read -r sid state; do
  [ -z "$sid" ] && continue
  case "$state" in
    done|wontfix) continue ;;
  esac
  wt=$(expand_path "$PATH_WORKTREES_TPL" "$FEATURE_SLUG" "$sid")
  if [ -d "$REPO_ROOT/$wt" ]; then
    BAIL_LIST+=("$sid (state=$state)")
  fi
done < <(yq -r '.stories[] | [.id, .state] | @tsv' "$MANIFEST")

if [ ${#BAIL_LIST[@]} -gt 0 ]; then
  log "ERROR: non-terminal stories still have worktrees — refusing to proceed"
  for s in "${BAIL_LIST[@]}"; do log "  - $s"; done
  log "let testing complete (or mark the slice wontfix) and re-run."
  exit 1
fi

# --- iterate stories --------------------------------------------------------

cleaned=0
skipped_state=0
skipped_missing=0
skipped_dirty=0
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

  # Refuse to tear down a dirty worktree — local changes the human didn't push.
  if [ "$wt_present" = 1 ] && [ -n "$(git -C "$REPO_ROOT/$wt" status --porcelain 2>/dev/null)" ]; then
    log "warn: $sid — worktree has uncommitted changes; skipping (resolve manually)"
    skipped_dirty=$((skipped_dirty + 1))
    SKIPPED_DETAIL+=("$sid: dirty worktree")
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "would clean: $sid (worktree=$wt_present branch=$br_present)"
    cleaned=$((cleaned + 1))
    continue
  fi

  # Copy runs/ back to integration tree before destroying the worktree.
  # Gitignored — present in working tree only. Inputs to `to-qa-handoff`.
  if [ "$wt_present" = 1 ]; then
    runs_rel=$(expand_path "$PATH_RUNS_TPL" "$FEATURE_SLUG" "$sid")
    src="$REPO_ROOT/$wt/$runs_rel/"
    dst="$REPO_ROOT/$runs_rel/"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a "$src" "$dst" \
        || { log "  warn: rsync failed for $sid"; }
    else
      log "  note: $sid has no runs dir in worktree; skipping copy-back"
    fi
  fi

  if [ "$wt_present" = 1 ]; then
    git worktree remove "$wt" 2>/dev/null \
      || { log "  warn: failed to remove worktree $wt"; }
  fi
  if [ "$br_present" = 1 ]; then
    git branch -D "$branch" 2>/dev/null \
      || { log "  warn: failed to delete branch $branch"; }
  fi
  log "cleaned: $sid (runs copied + worktree + branch)"
  cleaned=$((cleaned + 1))
done < <(yq -r '.stories[] | [.id, .state] | @tsv' "$MANIFEST")

# --- summary ----------------------------------------------------------------

echo "" >&2
log "summary: cleaned=$cleaned skipped_state=$skipped_state skipped_missing=$skipped_missing skipped_dirty=$skipped_dirty"
if [ ${#SKIPPED_DETAIL[@]} -gt 0 ]; then
  log "stories left intact:"
  for line in "${SKIPPED_DETAIL[@]}"; do
    log "  - $line"
  done
fi
log "feature integration branch ($(yq '.feature.branch' "$MANIFEST")) left alone — delete it manually after merging into protected."
if [ "$cleaned" -gt 0 ] && [ "$DRY_RUN" = 0 ]; then
  log "next: invoke \`to-qa-handoff\` to generate docs/ai-runs/$FEATURE_SLUG/qa-handoff.md"
fi
