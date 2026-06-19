#!/usr/bin/env bash
# AISDLC Phase 2 runner — manifest-driven, Bitbucket-backed.
#
# Reads docs/ai-runs/<feature-slug>/manifest.yaml. The script picks one
# eligible story at a time, spawns a fresh `codex` in a per-story worktree,
# runs post-agent gates, pushes the branch, opens or updates the PR, posts a
# typed `run-summary` PR comment, and flips manifest state. The loop is
# sequential per story but **non-blocking on PR merges** — it processes
# every story whose dependencies are already `done`, then exits with a
# named blocker when nothing's eligible.
#
# Re-runs from human feedback are detected by **PR comment watermark**: any
# User-type comment newer than the runner's latest `[Type: ...]` comment on
# the PR triggers another agent pass with the comment bundle inlined.
#
# In `--watch` mode the runner keeps polling only while at least one story is
# `pr-open` (a merge could still flip it `done` and unblock dependents). Once
# every story is `done` / `needs-info` / blocked by a non-`done` story — i.e.
# nothing left that polling can advance without human action — it exits with
# the named blocker instead of sleeping forever.
#
# Usage:
#   bash scripts/linux/run-codex-loop.sh                  # single-shot
#   bash scripts/linux/run-codex-loop.sh --watch 300      # poll every 300s until stuck

set -uo pipefail

# --- 0. constants + arg parsing ---------------------------------------------

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
AISDLC_JSON="$REPO_ROOT/.codex/aisdlc.json"

WATCH_INTERVAL=0   # 0 = single-shot

while [ "$#" -gt 0 ]; do
  case "$1" in
    --watch)
      shift
      WATCH_INTERVAL="${1:-}"
      if ! [[ "$WATCH_INTERVAL" =~ ^[0-9]+$ ]] || [ "$WATCH_INTERVAL" -lt 30 ]; then
        echo "error: --watch requires a positive integer >= 30 (seconds)" >&2
        exit 2
      fi
      shift
      ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# --- 1. logging primitives --------------------------------------------------

# Per-feature runner.log is opened once we know the feature slug. Until then
# logs go to stderr only.
RUNNER_LOG=""

log()  {
  local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  echo "$msg" >&2
  [ -n "$RUNNER_LOG" ] && echo "$msg" >> "$RUNNER_LOG"
}
fail() { log "ERROR: $*"; exit 1; }

windows_home_from_repo() {
  case "$REPO_ROOT" in
    /mnt/*/Users/*/*) echo "$REPO_ROOT" | sed -E 's#^(/mnt/[^/]+/Users/[^/]+).*$#\1#' ;;
    /?/[Uu]sers/*/*) echo "$REPO_ROOT" | sed -E 's#^(/[^/]+/[Uu]sers/[^/]+).*$#\1#' ;;
  esac
}

codex_config_candidates() {
  [ -n "${CODEX_CONFIG:-}" ] && echo "$CODEX_CONFIG"
  [ -n "${HOME:-}" ] && echo "$HOME/.codex/config.toml"
  local win_home
  win_home=$(windows_home_from_repo || true)
  [ -n "$win_home" ] && echo "$win_home/.codex/config.toml"
}

read_codex_config_key() {
  local key="$1" file value
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    value=$(sed -nE "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*$/\1/p" "$file" | tail -n 1)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done < <(codex_config_candidates | awk '!seen[$0]++')
  return 1
}

load_secret() {
  local var="$1" value
  value="${!var:-}"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  read_codex_config_key "$var"
}

# --- 2. tooling preflight ---------------------------------------------------

for tool in git jq yq codex timeout setsid curl; do
  command -v "$tool" >/dev/null || fail "$tool required on PATH"
done

[ -f "$AISDLC_JSON" ] || fail "missing $AISDLC_JSON"

APP_REPO_REL=$(jq -r '.repositories.application // "."' "$AISDLC_JSON")
case "$APP_REPO_REL" in
  /*|[A-Za-z]:*) APP_REPO_ROOT="$APP_REPO_REL" ;;
  *) APP_REPO_ROOT="$REPO_ROOT/$APP_REPO_REL" ;;
esac
[ -d "$APP_REPO_ROOT" ] || fail "application repository path does not exist: $APP_REPO_ROOT"

cd "$REPO_ROOT" || fail "cannot cd $REPO_ROOT"

git -C "$APP_REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not a git repository or not trusted by git: $APP_REPO_ROOT"

# --- 3. config load ---------------------------------------------------------

BRANCH_PREFIX=$(jq -r '.branches.prefix' "$AISDLC_JSON")
PROTECTED_BRANCHES=$(jq -r '.branches.protected[]' "$AISDLC_JSON" | paste -sd '|' -)
DIFF_FILE_CAP=$(jq -r '.caps.diffFiles' "$AISDLC_JSON")
DIFF_LINE_CAP=$(jq -r '.caps.diffLines' "$AISDLC_JSON")

# Generated paths (lockfiles, migrations, snapshots) are excluded from the
# human-review diff caps — they're not reviewed line-by-line and otherwise
# blow the budget. Loaded as git pathspec exclude args; empty if unconfigured.
DIFF_IGNORE_PATHSPEC=()
while IFS= read -r g; do
  [ -n "$g" ] && DIFF_IGNORE_PATHSPEC+=(":(exclude)$g")
done < <(jq -r '.caps.diffIgnoreGlobs[]?' "$AISDLC_JSON")
TDD_MAX_ATTEMPTS=$(jq -r '.caps.tddAttempts' "$AISDLC_JSON")
PER_STORY_WALL_CLOCK=$(jq -r '.caps.perStoryWallClockSec' "$AISDLC_JSON")
SANDBOX_MODE=$(jq -r '.runner.sandboxMode // "workspace-write"' "$AISDLC_JSON")
APPROVAL_POLICY=$(jq -r '.runner.approvalPolicy // "on-request"' "$AISDLC_JSON")
MODEL=$(jq -r '.runner.model // empty' "$AISDLC_JSON")

SCM_PROVIDER=$(jq -r '.sourceControl.provider // "bitbucket"' "$AISDLC_JSON")
if [ "$SCM_PROVIDER" != "bitbucket" ]; then
  fail "unsupported sourceControl.provider '$SCM_PROVIDER' (this runner expects bitbucket)"
fi
BB_BASE_URL=$(jq -r '.sourceControl.baseUrl // empty' "$AISDLC_JSON")
BB_PROJECT_KEY=$(jq -r '.sourceControl.projectKey // empty' "$AISDLC_JSON")
BB_REPO_SLUG=$(jq -r '.sourceControl.repositorySlug // empty' "$AISDLC_JSON")
BB_TOKEN_ENV=$(jq -r '.sourceControl.apiTokenEnv // "BITBUCKET_API_TOKEN"' "$AISDLC_JSON")
[ -n "$BB_BASE_URL" ] || fail "sourceControl.baseUrl required for Bitbucket"
[ -n "$BB_PROJECT_KEY" ] || fail "sourceControl.projectKey required for Bitbucket"
[ -n "$BB_REPO_SLUG" ] || fail "sourceControl.repositorySlug required for Bitbucket"
BB_BASE_URL="${BB_BASE_URL%/}"
BB_REST_PATH="/rest/api/latest/projects/$BB_PROJECT_KEY/repos/$BB_REPO_SLUG"
BB_TOKEN=$(load_secret "$BB_TOKEN_ENV" 2>/dev/null || true)
[ -n "$BB_TOKEN" ] || fail "$BB_TOKEN_ENV required in environment or Codex config for Bitbucket API"

PATH_MANIFEST_TPL=$(jq -r '.paths.manifest' "$AISDLC_JSON")
PATH_RUNS_TPL=$(jq -r '.paths.runs' "$AISDLC_JSON")
PATH_WORKTREES_TPL=$(jq -r '.paths.worktrees' "$AISDLC_JSON")
COMMENT_TYPE_RUN_SUMMARY=$(jq -r '.commentTypes.runSummary' "$AISDLC_JSON")
COMMENT_TYPE_DIAGNOSTICS=$(jq -r '.commentTypes.agentDiagnostics' "$AISDLC_JSON")

# expand_path TEMPLATE FEATURE_SLUG [STORY_ID]
# Substitutes {feature-slug} and {story-id} placeholders. Strips trailing
# slash so callers can compose paths consistently.
expand_path() {
  local t="$1" slug="$2" sid="${3:-}"
  t="${t//\{feature-slug\}/$slug}"
  t="${t//\{story-id\}/$sid}"
  echo "${t%/}"
}

# Lockfile lives at the literal root of the worktrees template (the segment
# before the first `{placeholder}`). This is single-instance across all
# features, not per-feature.
WORKTREES_ROOT="${PATH_WORKTREES_TPL%%\{*}"
WORKTREES_ROOT="${WORKTREES_ROOT%/}"
LOCKFILE="$REPO_ROOT/$WORKTREES_ROOT/.runner.lock"

# --- 4. branch + manifest resolution ----------------------------------------

INTEGRATION_BRANCH=$(git -C "$APP_REPO_ROOT" branch --show-current)
[ -n "$INTEGRATION_BRANCH" ] || fail "could not determine current branch (detached HEAD?)"

if echo "$INTEGRATION_BRANCH" | grep -qxE "$PROTECTED_BRANCHES"; then
  fail "refusing to run from protected branch '$INTEGRATION_BRANCH' — check out a feature branch first"
fi

# Find the manifest whose feature.branch matches the current branch.
# Glob is derived from paths.manifest with {feature-slug} → *.
MANIFEST_GLOB="$REPO_ROOT/${PATH_MANIFEST_TPL//\{feature-slug\}/*}"
MANIFEST=""
for candidate in $MANIFEST_GLOB; do
  [ -f "$candidate" ] || continue
  branch=$(yq '.feature.branch' "$candidate")
  if [ "$branch" = "$INTEGRATION_BRANCH" ]; then
    if [ -n "$MANIFEST" ]; then
      fail "multiple manifests claim feature.branch=$INTEGRATION_BRANCH: $MANIFEST and $candidate"
    fi
    MANIFEST="$candidate"
  fi
done
[ -n "$MANIFEST" ] || fail "no manifest under $MANIFEST_GLOB matches current branch '$INTEGRATION_BRANCH'"

FEATURE_SLUG=$(yq '.feature.slug' "$MANIFEST")
# RUNS_BASE = paths.runs with {feature-slug} substituted and {story-id} stripped.
RUNS_BASE=$(dirname "$(expand_path "$PATH_RUNS_TPL" "$FEATURE_SLUG" "X")")
RUNNER_LOG="$REPO_ROOT/$RUNS_BASE/runner.log"
mkdir -p "$(dirname "$RUNNER_LOG")"

log "feature=$FEATURE_SLUG integration=$INTEGRATION_BRANCH appRepo=$APP_REPO_ROOT manifest=$MANIFEST"

# --- 5. lockfile ------------------------------------------------------------

mkdir -p "$(dirname "$LOCKFILE")"
if [ -f "$LOCKFILE" ]; then
  prev_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$prev_pid" ] && kill -0 "$prev_pid" 2>/dev/null; then
    fail "another runner is active (pid $prev_pid). Remove $LOCKFILE if you're sure it isn't."
  fi
  log "stale lockfile at $LOCKFILE (pid $prev_pid no longer alive) — removing"
  rm -f "$LOCKFILE"
fi
echo "$$" > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# --- 6. Bitbucket API probe -------------------------------------------------

bb_api() {
  # $1 method, $2 REST path including query, optional $3 JSON body.
  local method="$1" path="$2" data="${3-}" url
  url="$BB_BASE_URL$path"
  if [ $# -ge 3 ]; then
    curl -fsS \
      -X "$method" \
      -H "Authorization: Bearer $BB_TOKEN" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      --data "$data" \
      "$url"
  else
    curl -fsS \
      -X "$method" \
      -H "Authorization: Bearer $BB_TOKEN" \
      -H "Accept: application/json" \
      "$url"
  fi
}

bb_api GET "$BB_REST_PATH" >/dev/null \
  || fail "could not read Bitbucket repo $BB_PROJECT_KEY/$BB_REPO_SLUG with $BB_TOKEN_ENV"
log "bitbucket repo: $BB_PROJECT_KEY/$BB_REPO_SLUG ($BB_BASE_URL)"

# --- 7. manifest helpers ----------------------------------------------------

manifest_story_field() {
  # $1 = story-id, $2 = field name (e.g., state, pr, blocked_by, validation)
  yq ".stories[] | select(.id == \"$1\") | .$2" "$MANIFEST"
}

manifest_set_state() {
  # $1 = story-id, $2 = new state
  yq -i "(.stories[] | select(.id == \"$1\") | .state) = \"$2\"" "$MANIFEST"
  log "state: $1 -> $2"
}

manifest_set_pr() {
  # $1 = story-id, $2 = pr number
  yq -i "(.stories[] | select(.id == \"$1\") | .pr) = $2" "$MANIFEST"
}

manifest_story_ids() {
  yq '.stories[].id' "$MANIFEST"
}

story_has_override() {
  # $1 = story-id, $2 = override token. Exact array-membership match against
  # .override (not a substring grep), absent/empty override → false.
  local sid="$1" token="$2" hit
  hit=$(yq ".stories[] | select(.id == \"$sid\") | .override[]? | select(. == \"$token\")" "$MANIFEST")
  [ -n "$hit" ]
}

manifest_state_of() {
  manifest_story_field "$1" state
}

manifest_predecessors_done() {
  # Returns 0 if every blocked_by ID for $1 is in state done.
  local preds
  preds=$(yq ".stories[] | select(.id == \"$1\") | .blocked_by[]" "$MANIFEST" 2>/dev/null || true)
  [ -z "$preds" ] && return 0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    local s
    s=$(manifest_state_of "$p")
    [ "$s" = "done" ] || return 1
  done <<< "$preds"
  return 0
}

manifest_first_undone_predecessor() {
  local preds
  preds=$(yq ".stories[] | select(.id == \"$1\") | .blocked_by[]" "$MANIFEST" 2>/dev/null || true)
  [ -z "$preds" ] && return 1
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    local s
    s=$(manifest_state_of "$p")
    [ "$s" != "done" ] && { echo "$p ($s)"; return 0; }
  done <<< "$preds"
  return 1
}

# --- 8. Bitbucket helpers ---------------------------------------------------

pr_exists() {
  # $1 = PR id; returns 0 if it exists in this repo.
  [ -n "$1" ] && [ "$1" != "null" ] \
    && bb_api GET "$BB_REST_PATH/pull-requests/$1" >/dev/null 2>&1
}

pr_is_merged() {
  # $1 = PR id
  local state
  state=$(bb_api GET "$BB_REST_PATH/pull-requests/$1" 2>/dev/null | jq -r '.state // empty' || echo "")
  [ "$state" = "MERGED" ]
}

bb_pr_activities_json() {
  # $1 = PR id; echoes a flat JSON array of activity values.
  local pr="$1" start=0 page is_last next out
  out='[]'
  while :; do
    page=$(bb_api GET "$BB_REST_PATH/pull-requests/$pr/activities?limit=100&start=$start") || return 1
    out=$(jq -s '.[0] + (.[1].values // [])' <<<"$out"$'\n'"$page")
    is_last=$(jq -r '.isLastPage // true' <<<"$page")
    [ "$is_last" = "true" ] && break
    next=$(jq -r '.nextPageStart // empty' <<<"$page")
    [ -n "$next" ] || break
    start="$next"
  done
  printf '%s\n' "$out"
}

bb_pr_comments_json() {
  # $1 = PR id; echoes normalized top-level Bitbucket comments.
  bb_pr_activities_json "$1" | jq '
    [
      .[]
      | select(.action == "COMMENTED")
      | select(.comment != null)
      | {
          id: (.comment.id // null),
          createdDate: (.comment.createdDate // 0),
          createdIso: (((.comment.createdDate // 0) / 1000) | todateiso8601),
          author: (.comment.author.displayName // .comment.author.name // .comment.author.emailAddress // "unknown"),
          text: (.comment.text // ""),
          anchor: (.commentAnchor // null),
          replies: [
            (.comment.comments // [])[]
            | {
                id: (.id // null),
                createdDate: (.createdDate // 0),
                createdIso: (((.createdDate // 0) / 1000) | todateiso8601),
                author: (.author.displayName // .author.name // .author.emailAddress // "unknown"),
                text: (.text // "")
              }
          ]
        }
    ]'
}

bb_find_open_pr_for_branch() {
  # $1 = from branch, $2 = target branch. Echoes PR id or empty.
  local from_ref="refs/heads/$1" to_ref="refs/heads/$2"
  local start=0 page is_last next hit
  while :; do
    page=$(bb_api GET "$BB_REST_PATH/pull-requests?state=OPEN&limit=100&start=$start") || return 1
    hit=$(jq -r --arg from_ref "$from_ref" --arg to_ref "$to_ref" '
      .values[]
      | select(.fromRef.id == $from_ref)
      | select(.toRef.id == $to_ref)
      | .id
    ' <<<"$page" | head -1)
    if [ -n "$hit" ]; then
      printf '%s\n' "$hit"
      return 0
    fi
    is_last=$(jq -r '.isLastPage // true' <<<"$page")
    [ "$is_last" = "true" ] && break
    next=$(jq -r '.nextPageStart // empty' <<<"$page")
    [ -n "$next" ] || break
    start="$next"
  done
}

# Returns the latest createdDate (epoch milliseconds) of any comment that starts
# with the `## [Type:` typed-header convention. Empty string if none.
pr_watermark() {
  local pr="$1"
  bb_pr_comments_json "$pr" 2>/dev/null \
    | jq -r '[.[] | select(.text | startswith("## [Type:")) | .createdDate] | max // empty'
}

# Echoes a markdown bundle of every post-watermark human comment.
# Empty output means no fresh feedback.
pr_human_feedback_bundle() {
  local pr="$1" watermark="$2" since comments replies all general inline
  since="${watermark:-0}"

  comments=$(bb_pr_comments_json "$pr") || return 1
  general=$(jq --argjson since "$since" '
    [
      .[]
      | select(.createdDate > $since)
      | select(.text | startswith("## [Type:") | not)
    ]' <<<"$comments")
  replies=$(jq --argjson since "$since" '
    [
      .[]
      | . as $parent
      | .replies[]
      | select(.createdDate > $since)
      | select(.text | startswith("## [Type:") | not)
      | . + {anchor: $parent.anchor, parentId: $parent.id}
    ]' <<<"$comments")
  all=$(jq -s 'add | sort_by(.createdDate)' <<<"$general"$'\n'"$replies")
  [ "$(jq 'length' <<<"$all")" -gt 0 ] || return 1

  general=$(jq '[.[] | select(.anchor == null)]' <<<"$all")
  inline=$(jq '[.[] | select(.anchor != null)]' <<<"$all")

  {
    echo "## Human feedback on PR #$pr since the last run-summary"

    if [ "$(jq 'length' <<<"$general")" -gt 0 ]; then
      echo ""
      echo "### General comments"
      jq -r '.[] | "- [\(.createdIso)] \(.author): \(.text | gsub("\r?\n"; "\n  "))"' <<<"$general"
    fi

    if [ "$(jq 'length' <<<"$inline")" -gt 0 ]; then
      echo ""
      echo "### Line comments (grouped by file)"
      jq -r '
        sort_by(.anchor.path // "unknown", .anchor.line // 0, .createdDate)
        | group_by(.anchor.path // "unknown")
        | .[] |
          "\n**\(.[0].anchor.path // "unknown")**\n" +
          (
            group_by(.anchor.line // 0)
            | map(
                "\nL\(.[0].anchor.line // "?"):\n" +
                (map("- [\(.createdIso)] \(.author): \(.text | gsub("\r?\n"; "\n  "))") | join("\n"))
              )
            | join("\n")
          )
      ' <<<"$inline"
    fi
  }
  return 0
}

# --- 9. worktree helpers ----------------------------------------------------

story_branch_name() {
  echo "${BRANCH_PREFIX}$1"   # e.g. codex/001-product-type-enum
}

worktree_path() {
  expand_path "$PATH_WORKTREES_TPL" "$FEATURE_SLUG" "$1"
}

story_runs_dir() {
  expand_path "$PATH_RUNS_TPL" "$FEATURE_SLUG" "$1"
}

worktree_exists() {
  [ -d "$REPO_ROOT/$(worktree_path "$1")" ]
}

ensure_worktree() {
  # $1 = story-id; creates the worktree off integration branch if needed.
  local sid="$1" wt branch
  wt=$(worktree_path "$sid")
  branch=$(story_branch_name "$sid")
  if worktree_exists "$sid"; then
    log "worktree $wt already exists — re-using"
    return 0
  fi
  # Branch may already exist from a prior partial run (worktree removed but
  # branch retained). `git worktree add` handles both with and without -b.
  if git -C "$APP_REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$APP_REPO_ROOT" worktree add "$REPO_ROOT/$wt" "$branch" \
      || fail "git worktree add $wt $branch failed"
  else
    git -C "$APP_REPO_ROOT" worktree add "$REPO_ROOT/$wt" -b "$branch" "$INTEGRATION_BRANCH" \
      || fail "git worktree add $wt -b $branch $INTEGRATION_BRANCH failed"
  fi
}

copy_path_to_worktree() {
  # $1 = worktree path, $2 = repo-relative path to copy.
  local wt="$1" rel="$2" src dst
  rel="${rel%/}"
  [ -n "$rel" ] || return 0
  case "$rel" in
    .worktrees|.worktrees/*)
      log "skip copy of recursive worktree path: $rel"
      return 0
      ;;
  esac
  src="$REPO_ROOT/$rel"
  dst="$REPO_ROOT/$wt/$rel"
  [ -e "$src" ] || return 0
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    cp -R "$src"/. "$dst"/
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

propagate_workspace_assets() {
  # Codex assets are usually gitignored in client repos, so `git worktree add`
  # will not carry them. Mirror the explicit allowlist into the story worktree.
  local sid="$1" wt include rel
  wt=$(worktree_path "$sid")
  include="$REPO_ROOT/.worktreeinclude"
  [ -f "$include" ] || fail "missing $include"
  while IFS= read -r rel || [ -n "$rel" ]; do
    rel="${rel%%#*}"
    rel="$(printf '%s' "$rel" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$rel" ] && continue
    copy_path_to_worktree "$wt" "$rel"
  done < "$include"
}

# Worktree teardown is owned by scripts/linux/cleanup-codex-worktrees.sh at end-of-feature.
# The runner never removes worktrees on its own — `testing.md` and other runs/
# artefacts written during preview must survive merge to feed `to-qa-handoff`.

# --- 10. gate checks --------------------------------------------------------

# Each gate function: arg1=worktree-path, arg2=story-id, arg3=run-number.
# On failure: echoes a one-line reason on stdout AND returns 1.

gate_commits_exist() {
  local wt="$1" branch
  branch=$(story_branch_name "$2")
  local n
  n=$(git -C "$REPO_ROOT/$wt" rev-list --count "$INTEGRATION_BRANCH..$branch" 2>/dev/null || echo 0)
  if [ "$n" -lt 1 ]; then
    echo "no new commits on $branch since fork from $INTEGRATION_BRANCH"
    return 1
  fi
}

gate_commit_messages_reference_story() {
  local wt="$1" sid="$2" branch
  branch=$(story_branch_name "$sid")
  local bad
  bad=$(git -C "$REPO_ROOT/$wt" log --format=%s "$INTEGRATION_BRANCH..$branch" \
        | grep -vF "$sid" | head -1)
  if [ -n "$bad" ]; then
    echo "commit message does not reference story id '$sid': '$bad'"
    return 1
  fi
}

gate_diff_within_caps() {
  local wt="$1" sid="$2"
  if story_has_override "$sid" "large-diff-ok"; then
    return 0
  fi
  # Exclude generated paths from the counted diff (see DIFF_IGNORE_PATHSPEC).
  local pathspec=()
  if [ "${#DIFF_IGNORE_PATHSPEC[@]}" -gt 0 ]; then
    pathspec=(-- . "${DIFF_IGNORE_PATHSPEC[@]}")
  fi
  local branch files lines
  branch=$(story_branch_name "$sid")
  files=$(git -C "$REPO_ROOT/$wt" diff --name-only "$INTEGRATION_BRANCH..$branch" "${pathspec[@]}" | wc -l)
  lines=$(git -C "$REPO_ROOT/$wt" diff --shortstat "$INTEGRATION_BRANCH..$branch" "${pathspec[@]}" \
          | grep -oE '[0-9]+ (insertions|deletions)' \
          | awk '{ s += $1 } END { print s+0 }')
  if [ "$files" -gt "$DIFF_FILE_CAP" ]; then
    echo "diff exceeds file cap: $files > $DIFF_FILE_CAP (add 'large-diff-ok' override to bypass)"
    return 1
  fi
  if [ "$lines" -gt "$DIFF_LINE_CAP" ]; then
    echo "diff exceeds line cap: $lines > $DIFF_LINE_CAP (add 'large-diff-ok' override to bypass)"
    return 1
  fi
}

gate_no_harness_assets_committed() {
  local wt="$1" sid="$2" branch bad
  branch=$(story_branch_name "$sid")
  bad=$(git -C "$REPO_ROOT/$wt" diff --name-only "$INTEGRATION_BRANCH..$branch" -- .codex AGENTS.md .worktreeinclude CONTEXT.md docs scripts | head -1)
  if [ -n "$bad" ]; then
    echo "harness asset committed to application branch: $bad"
    return 1
  fi
}

gate_run_log_present() {
  local wt="$1" sid="$2" n="$3"
  if [ ! -f "$REPO_ROOT/$wt/$(story_runs_dir "$sid")/run-$n.md" ]; then
    echo "run log missing: $(story_runs_dir "$sid")/run-$n.md not written"
    return 1
  fi
}

gate_worktree_clean() {
  local wt="$1"
  local dirty
  dirty=$(git -C "$REPO_ROOT/$wt" status --porcelain -- . ":(exclude).codex" ":(exclude)AGENTS.md" ":(exclude).worktreeinclude" ":(exclude)CONTEXT.md" ":(exclude)docs" ":(exclude)scripts" | head -1)
  if [ -n "$dirty" ]; then
    echo "worktree has uncommitted changes: '$dirty'"
    return 1
  fi
}

run_gates() {
  # $1 wt, $2 sid, $3 run-num, $4 codex-exit-code.
  # Echoes empty on success; otherwise echoes the first failed gate's reason.
  local wt="$1" sid="$2" n="$3" rc="$4"
  if [ "$rc" -ne 0 ]; then
    echo "codex exited rc=$rc (likely wall-clock kill or uncaught error)"
    return 1
  fi
  local reason
  reason=$(gate_commits_exist "$wt" "$sid")              || { echo "$reason"; return 1; }
  reason=$(gate_commit_messages_reference_story "$wt" "$sid") || { echo "$reason"; return 1; }
  reason=$(gate_no_harness_assets_committed "$wt" "$sid") || { echo "$reason"; return 1; }
  reason=$(gate_diff_within_caps "$wt" "$sid")           || { echo "$reason"; return 1; }
  reason=$(gate_run_log_present "$wt" "$sid" "$n")       || { echo "$reason"; return 1; }
  reason=$(gate_worktree_clean "$wt")                    || { echo "$reason"; return 1; }
  return 0
}

# --- 11. spawn prompt + codex --------------------------------------------

next_run_number() {
  # Counts the highest existing run-N.* (md or stream.jsonl) and adds 1.
  # Using max-existing rather than count-existing means a prior F1 that left
  # only a stream-jsonl behind doesn't get overwritten on the next attempt.
  local sid="$1" dir max
  dir="$REPO_ROOT/$(worktree_path "$sid")/$(story_runs_dir "$sid")"
  if [ ! -d "$dir" ]; then echo 1; return; fi
  max=$(find "$dir" -maxdepth 1 -name 'run-*' 2>/dev/null \
        | sed -nE 's|.*/run-([0-9]+)\..*|\1|p' \
        | sort -n | tail -1)
  if [ -z "$max" ]; then echo 1; else echo $((max + 1)); fi
}

build_spawn_prompt() {
  # $1 sid, $2 run-num, $3 feedback-bundle-or-empty
  local sid="$1" n="$2" feedback="$3"
  local branch
  branch=$(story_branch_name "$sid")
  local override="0"
  if story_has_override "$sid" "large-diff-ok"; then
    override="1"
  fi
  # Point Codex at the local skill file so the runner works without legacy defaults.
  cat <<EOF
Read and follow the local implementation skill before making changes:

  .codex/skills/implement-story/SKILL.md

You are the Phase 2 implementation agent for story $sid under feature
$FEATURE_SLUG. Run #$n in this worktree.

Story branch: $branch
Integration branch: $INTEGRATION_BRANCH
Diff cap override (large-diff-ok): $override
Diff cap: $DIFF_FILE_CAP files / $DIFF_LINE_CAP lines
TDD attempt cap: $TDD_MAX_ATTEMPTS

Your spec is on disk at:

  $(story_runs_dir "$sid")/implementation.md

Do not push, do not open or update any PR, do not post any comment — the
harness owns every remote-side write. Your job is: ground the touch
surface, vertical-slice TDD per logical unit, commit locally, write the
next run log at $(story_runs_dir "$sid")/run-$n.md, then exit.

Do not commit AGENTS.md, .worktreeinclude, CONTEXT.md, docs/, scripts/, or
anything under .codex/. Those files are copied into this worktree as harness
context only.
EOF

  if [ -n "$feedback" ]; then
    cat <<EOF

The human left feedback on the PR since the last run-summary. Treat this
as a narrative redirect for this iteration. Default behaviour is
keep-working-from-where-you-left-off.

$feedback

Also read the prior run logs under $(story_runs_dir "$sid")/ (run-1.md, run-2.md,
...) before making changes.
EOF
  fi

}

# Legacy stream formatter retained from the original runner; Codex JSONL is logged raw.
# Reads codex's per-event JSONL on stdin, emits one human-readable line
# per init / assistant turn / tool call / result event to stderr.
stream_format() {
  jq -r --unbuffered '
    def fmt_tool($n; $i):
      if   $n == "Read"       then "Read(\($i.file_path // "?"))"
      elif $n == "Write"      then "Write(\($i.file_path // "?"))"
      elif $n == "Edit"       then "Edit(\($i.file_path // "?"))"
      elif $n == "MultiEdit"  then "MultiEdit(\($i.file_path // "?"))"
      elif $n == "Bash"       then
        "Bash(" + (($i.command // "?") | gsub("\\s+"; " ")
                   | if length > 100 then .[0:97] + "..." else . end) + ")"
      elif $n == "Grep"       then
        "Grep(\"\($i.pattern // "?")\""
        + (if ($i.path // "") != "" then " in \($i.path)" else "" end)
        + (if ($i.glob // "") != "" then " --glob \($i.glob)" else "" end)
        + ")"
      elif $n == "Glob"       then "Glob(\($i.pattern // "?"))"
      elif $n == "Skill"      then
        "Skill(/\($i.skill // "?")"
        + (if ($i.args // "") != "" then " "
             + (($i.args | tostring)
                | if length > 60 then .[0:57] + "..." else . end)
           else "" end)
        + ")"
      elif $n == "Agent"      then
        "Agent(\($i.subagent_type // "default")"
        + (if ($i.description // "") != "" then " — \($i.description)" else "" end)
        + ")"
      elif $n == "WebFetch"   then "WebFetch(\($i.url // "?"))"
      elif $n == "WebSearch"  then "WebSearch(\"\($i.query // "?")\")"
      elif $n == "TodoWrite"  then "TodoWrite(\(($i.todos // []) | length) items)"
      elif $n == "TaskCreate" then "TaskCreate(\($i.description // "?"))"
      else $n + "(\($i | keys | join(",")))"
      end;
    if .type == "system" and .subtype == "init" then
      "[\(now | strftime("%H:%M:%SZ"))] init   model=\(.model // "?") session=\(((.session_id // "?") | .[0:8]))"
    elif .type == "assistant" then
      (.message.usage // {}) as $u
      | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) as $ctx
      | (($ctx / 1000) | floor) as $ctxk
      | (now | strftime("%H:%M:%SZ")) as $ts
      | ([.message.content[]? | select(.type == "tool_use")] | length > 0) as $has_tool
      | (if $has_tool then empty else "[\($ts)] turn (\($ctxk)k tok)" end),
        ( .message.content[]?
          | if .type == "tool_use" then
              "[\($ts)] turn (\($ctxk)k tok) -> " + fmt_tool(.name; (.input // {}))
            elif .type == "text" and ((.text // "") | length > 0) then
              (.text | gsub("^\\s+|\\s+$"; ""))
              | split("\n") | .[] | "             > " + .
            else empty
            end )
    elif .type == "result" then
      "[\(now | strftime("%H:%M:%SZ"))] done   subtype=\(.subtype // "?") cost=$\(.total_cost_usd // 0) duration=\(((.duration_ms // 0) / 1000) | floor)s turns=\(.num_turns // 0)"
    else empty end' >&2
}

spawn_codex() {
  # $1 sid, $2 prompt-file, $3 run-num. Returns codex's exit code.
  local sid="$1" prompt_file="$2" n="$3" wt rc stream_log
  wt=$(worktree_path "$sid")
  stream_log="$REPO_ROOT/$wt/$(story_runs_dir "$sid")/run-$n.stream.jsonl"
  mkdir -p "$(dirname "$stream_log")"
  log "spawning codex in $wt (run $n, stream-log: $stream_log)"

  # Echo the exact prompt being piped to codex, to stderr and runner.log.
  # Bracketed so it reads as one block rather than per-line timestamps.
  {
    echo "----- prompt for $sid run $n (begin) -----"
    cat "$prompt_file"
    echo "----- prompt for $sid run $n (end) -----"
  } | tee -a "${RUNNER_LOG:-/dev/null}" >&2

  rc=0
  local pgid_file; pgid_file=$(mktemp)
  local codex_args
  codex_args=(exec --sandbox "$SANDBOX_MODE" --ask-for-approval "$APPROVAL_POLICY" -C "$REPO_ROOT/$wt" --json)
  if [ -n "$MODEL" ]; then
    codex_args+=(--model "$MODEL")
  fi
  codex_args+=(-)
  # Run the agent in its own session/process group (setsid) and record the
  # group-leader PID. The inner `sh` becomes the leader, writes its own PID,
  # then exec's `timeout codex` in place (same PID → same PGID). codex and any
  # process it spawns inherit that PGID, so we can sweep the whole subtree below.
  ( cd "$REPO_ROOT/$wt" \
    && setsid -w sh -c 'echo "$$" >"$1"; shift; exec timeout "$@"' \
         sh "$pgid_file" "$PER_STORY_WALL_CLOCK" \
         codex "${codex_args[@]}" \
         < "$prompt_file" ) \
    | tee "$stream_log" \
    || rc=$?
  # Defense-in-depth: an agent must not leave anything running (see the
  # implement-story "Boundaries" section). A well-behaved run makes this a
  # no-op. If an agent leaked a long-lived child (e.g. a dev server), it lingers
  # here — or, in the worst case, held the agent open until the wall-clock
  # `timeout` above fired; either way we reap the orphaned group so it can't
  # leak ports or wedge a later iteration.
  local agent_pgid; agent_pgid=$(cat "$pgid_file" 2>/dev/null); rm -f "$pgid_file"
  if [ -n "$agent_pgid" ] && kill -0 "-$agent_pgid" 2>/dev/null; then
    log "reaping leftover processes in agent group $agent_pgid"
    kill -TERM "-$agent_pgid" 2>/dev/null || true
    sleep 2
    kill -KILL "-$agent_pgid" 2>/dev/null || true
  fi
  log "codex exited rc=$rc"
  return $rc
}

# --- 12. push + PR + comment ------------------------------------------------

push_branch() {
  # $1 sid; returns 0 on success.
  local sid="$1" wt branch
  wt=$(worktree_path "$sid")
  branch=$(story_branch_name "$sid")
  ( cd "$REPO_ROOT/$wt" && git push -u origin "$branch" ) \
    || { log "git push failed for $branch"; return 1; }
}

open_or_update_pr() {
  # $1 sid; sets the manifest .pr field on first create. Returns 0 on success.
  local sid="$1" existing pr_num
  existing=$(manifest_story_field "$sid" pr)
  if pr_exists "$existing"; then
    log "PR #$existing already open for $sid — push updated it"
    return 0
  fi

  local title body wt branch
  branch=$(story_branch_name "$sid")
  wt=$(worktree_path "$sid")
  title="$sid: $(yq ".stories[] | select(.id == \"$sid\") | .title" "$MANIFEST")"

  local description
  description=$(yq ".stories[] | select(.id == \"$sid\") | .description" "$MANIFEST")

  local preds_list
  preds_list=$(yq ".stories[] | select(.id == \"$sid\") | .blocked_by[]?" "$MANIFEST" 2>/dev/null \
               | paste -sd ', ' -)
  [ -z "$preds_list" ] && preds_list="none"

  body=$(cat <<EOF
> *Generated by AI during the AISDLC workflow.*

## Summary
- $description

## Linked work
- Story: \`$sid\` (feature \`$FEATURE_SLUG\`, manifest at \`$MANIFEST\`)
- Predecessors merged: $preds_list

## Verification
- Per-run details are posted as separate \`run-summary\` comments below.
- Test plan: posted on this PR after Phase 3 \`test-item\` runs.
EOF
)

  existing=$(bb_find_open_pr_for_branch "$branch" "$INTEGRATION_BRANCH" 2>/dev/null || true)
  if [ -n "$existing" ]; then
    manifest_set_pr "$sid" "$existing"
    log "PR #$existing already open for $sid — manifest updated"
    return 0
  fi

  local payload create_out
  payload=$(jq -n \
    --arg title "$title" \
    --arg description "$body" \
    --arg from_ref "refs/heads/$branch" \
    --arg to_ref "refs/heads/$INTEGRATION_BRANCH" \
    --arg project_key "$BB_PROJECT_KEY" \
    --arg repo_slug "$BB_REPO_SLUG" \
    '{
      title: $title,
      description: $description,
      state: "OPEN",
      open: true,
      closed: false,
      fromRef: {
        id: $from_ref,
        repository: { slug: $repo_slug, project: { key: $project_key } }
      },
      toRef: {
        id: $to_ref,
        repository: { slug: $repo_slug, project: { key: $project_key } }
      }
    }')
  create_out=$(bb_api POST "$BB_REST_PATH/pull-requests" "$payload" 2>&1) \
    || { log "Bitbucket PR create failed for $branch: $create_out"; return 1; }
  pr_num=$(jq -r '.id // empty' <<<"$create_out")

  if [ -z "$pr_num" ]; then
    log "Bitbucket PR create did not return a PR id for $branch"
    return 1
  fi

  manifest_set_pr "$sid" "$pr_num"
  log "PR #$pr_num opened for $sid"
}

post_run_summary() {
  # $1 sid, $2 run-num. Reads the run log, prepends the typed header, posts.
  local sid="$1" n="$2" pr body run_log
  pr=$(manifest_story_field "$sid" pr)
  pr_exists "$pr" || { log "post_run_summary: no PR for $sid (pr=$pr)"; return 1; }
  run_log="$REPO_ROOT/$(worktree_path "$sid")/$(story_runs_dir "$sid")/run-$n.md"
  [ -f "$run_log" ] || { log "post_run_summary: $run_log missing"; return 1; }

  body=$(printf '## [Type: %s | by: scripts/linux/run-codex-loop.sh | run %s]\n\n%s' \
           "$COMMENT_TYPE_RUN_SUMMARY" "$n" "$(cat "$run_log")")
  bb_api POST "$BB_REST_PATH/pull-requests/$pr/comments" "$(jq -n --arg text "$body" '{text: $text}')" >/dev/null \
    || { log "Bitbucket PR comment failed for PR #$pr"; return 1; }
  log "run-summary posted on PR #$pr (run $n)"
}

post_diagnostics_comment() {
  # $1 sid, $2 run-num, $3 reason
  local sid="$1" n="$2" reason="$3" pr body
  pr=$(manifest_story_field "$sid" pr)
  pr_exists "$pr" || return 0   # no PR to comment on
  body=$(cat <<EOF
## [Type: $COMMENT_TYPE_DIAGNOSTICS | by: scripts/linux/run-codex-loop.sh | run $n]

> *Generated by AI during the AISDLC workflow.*

Agent run #$n for \`$sid\` did not pass post-agent gates.

- **Gate failure:** $reason
- **Worktree:** \`$(worktree_path "$sid")\` (left intact)
- **Branch:** \`$(story_branch_name "$sid")\` (kept; commits, if any, preserved)
- **Stream log:** \`$(story_runs_dir "$sid")/run-$n.stream.jsonl\`

State: \`agent-dev\` → \`needs-info\`. Fix the blocker, then either re-tag
\`ready-for-agent\` in the manifest, or post a comment here to give it
another pass (the next runner iteration will pick the fresh feedback up).
EOF
)
  bb_api POST "$BB_REST_PATH/pull-requests/$pr/comments" "$(jq -n --arg text "$body" '{text: $text}')" >/dev/null || true
}

# --- 13. iteration body -----------------------------------------------------

# Ensure the integration branch exists on origin. Every story PR opens with it
# as the target branch, so Bitbucket PR create fails if it was never pushed. Push it
# once up front rather than discovering the failure per-story.
ensure_integration_pushed() {
  if git -C "$APP_REPO_ROOT" ls-remote --exit-code --heads origin "$INTEGRATION_BRANCH" >/dev/null 2>&1; then
    log "integration branch '$INTEGRATION_BRANCH' present on origin"
    return 0
  fi
  log "integration branch '$INTEGRATION_BRANCH' not on origin — pushing"
  ( cd "$APP_REPO_ROOT" && git push -u origin "$INTEGRATION_BRANCH" ) \
    || fail "failed to push integration branch '$INTEGRATION_BRANCH' to origin"
}

# Reconcile pr-open stories: detect merges, flip done, cleanup.
sync_remote() {
  log "sync: git fetch + reconcile pr-open stories"
  git -C "$APP_REPO_ROOT" fetch origin "$INTEGRATION_BRANCH" 2>/dev/null || true
  # Fast-forward pull only.
  git -C "$APP_REPO_ROOT" pull --ff-only origin "$INTEGRATION_BRANCH" 2>/dev/null || true

  local sid pr state
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    state=$(manifest_state_of "$sid")
    [ "$state" = "pr-open" ] || continue
    pr=$(manifest_story_field "$sid" pr)
    pr_exists "$pr" || continue
    if pr_is_merged "$pr"; then
      log "PR #$pr merged → $sid done (worktree retained for end-of-feature cleanup)"
      manifest_set_state "$sid" "done"
    fi
  done < <(manifest_story_ids)
}

# Pick next eligible story. Echoes story-id on stdout, empty if none.
pick_next_story() {
  local sid state pr
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    state=$(manifest_state_of "$sid")
    case "$state" in
      ready-for-agent)
        manifest_predecessors_done "$sid" && { echo "$sid"; return 0; }
        ;;
      agent-dev)
        # Recovery: prior iteration crashed mid-flight, worktree present.
        worktree_exists "$sid" && { echo "$sid"; return 0; }
        ;;
      pr-open)
        manifest_predecessors_done "$sid" || continue
        pr=$(manifest_story_field "$sid" pr)
        pr_exists "$pr" || continue
        local watermark bundle
        watermark=$(pr_watermark "$pr")
        bundle=$(pr_human_feedback_bundle "$pr" "$watermark") && { echo "$sid"; return 0; }
        ;;
    esac
  done < <(manifest_story_ids)
  return 1
}

# Report why we're exiting (named blocker).
report_exit_reason() {
  local sid state
  local blocked_count=0 needs_info_count=0 pr_open_count=0
  local first_blocker_id="" first_blocker_pred=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    state=$(manifest_state_of "$sid")
    case "$state" in
      ready-for-agent)
        if ! manifest_predecessors_done "$sid"; then
          blocked_count=$((blocked_count + 1))
          if [ -z "$first_blocker_id" ]; then
            first_blocker_id="$sid"
            first_blocker_pred=$(manifest_first_undone_predecessor "$sid" || echo "?")
          fi
        fi
        ;;
      needs-info) needs_info_count=$((needs_info_count + 1)) ;;
      pr-open)    pr_open_count=$((pr_open_count + 1)) ;;
    esac
  done < <(manifest_story_ids)

  # Expose the pr-open tally so main_loop can decide whether --watch has
  # anything left to advance: a pr-open story can flip to done on an external
  # merge, but needs-info / blocked stories only move on human action, which
  # polling can't observe as forward progress.
  PR_OPEN_REMAINING=$pr_open_count

  log "exit summary: pr-open=$pr_open_count needs-info=$needs_info_count blocked=$blocked_count"
  if [ "$pr_open_count" -gt 0 ]; then
    log "  → $pr_open_count story PR(s) awaiting human review/merge"
  fi
  if [ -n "$first_blocker_id" ]; then
    log "  → next eligible: $first_blocker_id (blocked on $first_blocker_pred)"
  fi
  if [ "$needs_info_count" -gt 0 ]; then
    log "  → $needs_info_count story/stories in needs-info — see runner.log for details"
  fi
}

# Run one iteration. Returns 0 if an agent ran (success or F1), 1 if no work.
run_one_iteration() {
  sync_remote

  local sid
  sid=$(pick_next_story) || return 1
  log "==> picking $sid (current state: $(manifest_state_of "$sid"))"

  # Brief audit.
  if [ ! -f "$REPO_ROOT/$(story_runs_dir "$sid")/implementation.md" ]; then
    log "brief audit failed: $(story_runs_dir "$sid")/implementation.md missing"
    manifest_set_state "$sid" "needs-info"
    return 0
  fi

  # Claim (unless already agent-dev from recovery).
  local prior_state
  prior_state=$(manifest_state_of "$sid")
  if [ "$prior_state" != "agent-dev" ]; then
    manifest_set_state "$sid" "agent-dev"
  fi

  ensure_worktree "$sid"
  propagate_workspace_assets "$sid"

  local n
  n=$(next_run_number "$sid")

  # Build feedback bundle if this is a pr-open re-run.
  local feedback=""
  if [ "$prior_state" = "pr-open" ]; then
    local pr watermark
    pr=$(manifest_story_field "$sid" pr)
    watermark=$(pr_watermark "$pr")
    feedback=$(pr_human_feedback_bundle "$pr" "$watermark" 2>/dev/null || true)
  fi

  local prompt_file
  prompt_file=$(mktemp)
  trap 'rm -f "$prompt_file"' RETURN
  build_spawn_prompt "$sid" "$n" "$feedback" > "$prompt_file"

  local rc=0
  spawn_codex "$sid" "$prompt_file" "$n" || rc=$?

  # Gate checks.
  local wt reason
  wt=$(worktree_path "$sid")
  if ! reason=$(run_gates "$wt" "$sid" "$n" "$rc"); then
    log "gate failure for $sid: $reason"
    # Try to post diagnostics if a PR exists (only on re-runs).
    if [ "$prior_state" = "pr-open" ]; then
      post_diagnostics_comment "$sid" "$n" "$reason"
    fi
    manifest_set_state "$sid" "needs-info"
    return 0
  fi

  # Push, then open/update PR.
  if ! push_branch "$sid"; then
    manifest_set_state "$sid" "needs-info"
    return 0
  fi
  if ! open_or_update_pr "$sid"; then
    manifest_set_state "$sid" "needs-info"
    return 0
  fi

  # Post the run-summary comment.
  post_run_summary "$sid" "$n" || true

  manifest_set_state "$sid" "pr-open"
  log "==> $sid pr-open (run $n complete)"
  return 0
}

# --- 14. outer loop ---------------------------------------------------------

main_loop() {
  ensure_integration_pushed
  while : ; do
    if run_one_iteration; then
      # Did work — keep going.
      continue
    fi
    # No eligible work.
    report_exit_reason
    if [ "$WATCH_INTERVAL" -eq 0 ]; then
      log "no eligible work — single-shot exit"
      break
    fi
    # In --watch mode, only keep polling while a pr-open story could still flip
    # to done on an external merge. If none remain, every story is done /
    # needs-info / blocked-by-a-non-done story, so nothing will advance without
    # human action — exit rather than poll forever.
    if [ "${PR_OPEN_REMAINING:-0}" -eq 0 ]; then
      log "no eligible work and no open PRs — nothing left for --watch to advance; exiting"
      break
    fi
    log "no eligible work — sleeping ${WATCH_INTERVAL}s (--watch); $PR_OPEN_REMAINING open PR(s) may still merge"
    sleep "$WATCH_INTERVAL"
  done
}

main_loop
log "runner exiting; feature=$FEATURE_SLUG"
