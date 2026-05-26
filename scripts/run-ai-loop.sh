#!/usr/bin/env bash
# AISDLC Phase 2 runner — manifest-driven, GitHub-default.
#
# Reads docs/ai-runs/<feature-slug>/manifest.yaml. The script picks one
# eligible story at a time, spawns a fresh `claude` in a per-story worktree,
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
# Usage:
#   bash scripts/run-ai-loop.sh                  # single-shot
#   bash scripts/run-ai-loop.sh --watch 300      # long-running, poll every 300s

set -uo pipefail

# --- 0. constants + arg parsing ---------------------------------------------

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AISDLC_JSON="$REPO_ROOT/.claude/aisdlc.json"

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

# --- 2. tooling preflight ---------------------------------------------------

for tool in git gh jq yq claude timeout; do
  command -v "$tool" >/dev/null || fail "$tool required on PATH"
done

[ -f "$AISDLC_JSON" ] || fail "missing $AISDLC_JSON"

if ! gh auth status >/dev/null 2>&1; then
  fail "gh is not authenticated — run \`gh auth login\` first"
fi

cd "$REPO_ROOT" || fail "cannot cd $REPO_ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not a git repository: $REPO_ROOT"

# --- 3. config load ---------------------------------------------------------

BRANCH_PREFIX=$(jq -r '.branches.prefix' "$AISDLC_JSON")
PROTECTED_BRANCHES=$(jq -r '.branches.protected[]' "$AISDLC_JSON" | paste -sd '|' -)
DIFF_FILE_CAP=$(jq -r '.caps.diffFiles' "$AISDLC_JSON")
DIFF_LINE_CAP=$(jq -r '.caps.diffLines' "$AISDLC_JSON")
TDD_MAX_ATTEMPTS=$(jq -r '.caps.tddAttempts' "$AISDLC_JSON")
PER_STORY_WALL_CLOCK=$(jq -r '.caps.perStoryWallClockSec' "$AISDLC_JSON")
PERMISSION_MODE=$(jq -r '.runner.permissionMode // "acceptEdits"' "$AISDLC_JSON")

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

INTEGRATION_BRANCH=$(git branch --show-current)
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

log "feature=$FEATURE_SLUG integration=$INTEGRATION_BRANCH manifest=$MANIFEST"

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

# --- 6. gh remote derivation ------------------------------------------------

# `gh` needs to know which repo. We rely on it inferring from the local
# remote (`gh repo view` returns it). Cache the owner/repo for API calls.
GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
  || fail "could not determine GH repo via \`gh repo view\` — is the remote configured?"
log "gh repo: $GH_REPO"

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

# --- 8. GitHub helpers ------------------------------------------------------

pr_exists() {
  # $1 = pr number; returns 0 if it exists in this repo.
  [ -n "$1" ] && [ "$1" != "null" ] \
    && gh pr view "$1" -R "$GH_REPO" --json number >/dev/null 2>&1
}

pr_is_merged() {
  # $1 = pr number
  local state
  state=$(gh pr view "$1" -R "$GH_REPO" --json state -q .state 2>/dev/null || echo "")
  [ "$state" = "MERGED" ]
}

# Returns the latest createdAt (ISO-8601) of any comment authored by us that
# starts with the `## [Type:` typed-header convention. Empty string if none.
pr_watermark() {
  local pr="$1"
  {
    gh api "repos/$GH_REPO/issues/$pr/comments" \
      --paginate -q '.[] | select(.body | startswith("## [Type:")) | .created_at'
    gh api "repos/$GH_REPO/pulls/$pr/comments" \
      --paginate -q '.[] | select(.body | startswith("## [Type:")) | .created_at'
  } 2>/dev/null | sort -r | head -1
}

# Echoes a markdown bundle of every post-watermark User-authored comment.
# Empty output means no fresh feedback.
pr_human_feedback_bundle() {
  local pr="$1" watermark="$2"
  local since_filter='true'
  if [ -n "$watermark" ]; then
    # jq comparison on ISO-8601 strings is lexicographic, which is correct.
    since_filter=".created_at > \"$watermark\""
  fi

  local issue_comments review_comments review_summaries
  issue_comments=$(gh api "repos/$GH_REPO/issues/$pr/comments" --paginate \
    -q "[.[] | select(.user.type == \"User\") | select($since_filter) | select(.body | startswith(\"## [Type:\") | not)]")
  review_comments=$(gh api "repos/$GH_REPO/pulls/$pr/comments" --paginate \
    -q "[.[] | select(.user.type == \"User\") | select($since_filter)]")
  review_summaries=$(gh api "repos/$GH_REPO/pulls/$pr/reviews" --paginate \
    -q "[.[] | select(.user.type == \"User\") | select(.submitted_at != null) | select(.submitted_at > \"${watermark:-0000}\") | select(.body != null and .body != \"\")]")

  # Bail early if nothing post-watermark.
  local total
  total=$(jq -s 'add | length' <<<"$issue_comments"$'\n'"$review_comments"$'\n'"$review_summaries")
  [ "$total" -gt 0 ] || return 1

  {
    echo "## Human feedback on PR #$pr since the last run-summary"

    if [ "$(jq 'length' <<<"$issue_comments")" -gt 0 ]; then
      echo ""
      echo "### General comments"
      jq -r '.[] | "- [\(.created_at)] \(.user.login): \(.body | gsub("\n"; "\n  "))"' <<<"$issue_comments"
    fi

    if [ "$(jq 'length' <<<"$review_comments")" -gt 0 ]; then
      echo ""
      echo "### Line comments (grouped by file)"
      # Group by path, then by line, preserve chronological order within.
      jq -r '
        sort_by(.path, .line // .original_line, .created_at)
        | group_by(.path)
        | .[] |
          "\n**\(.[0].path)**\n" +
          (
            group_by(.line // .original_line)
            | map(
                "\nL\(.[0].line // .[0].original_line):\n```diff\n\(.[0].diff_hunk // "")\n```\n" +
                (map("- [\(.created_at)] \(.user.login): \(.body | gsub("\n"; "\n  "))") | join("\n"))
              )
            | join("\n")
          )
      ' <<<"$review_comments"
    fi

    if [ "$(jq 'length' <<<"$review_summaries")" -gt 0 ]; then
      echo ""
      echo "### Review summaries"
      jq -r '.[] | "- [\(.submitted_at)] \(.user.login) (\(.state)): \(.body | gsub("\n"; "\n  "))"' <<<"$review_summaries"
    fi
  }
  return 0
}

# --- 9. worktree helpers ----------------------------------------------------

story_branch_name() {
  echo "${BRANCH_PREFIX}$1"   # e.g. claude/001-product-type-enum
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
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$wt" "$branch" \
      || fail "git worktree add $wt $branch failed"
  else
    git worktree add "$wt" -b "$branch" "$INTEGRATION_BRANCH" \
      || fail "git worktree add $wt -b $branch $INTEGRATION_BRANCH failed"
  fi
}

propagate_runs_dir() {
  # The runs dir is gitignored, so `git worktree add` doesn't carry it.
  local sid="$1" wt
  wt=$(worktree_path "$sid")
  local src="$REPO_ROOT/$(story_runs_dir "$sid")"
  local dst="$REPO_ROOT/$wt/$RUNS_BASE"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  cp -R "$src" "$dst/"
}

# Worktree teardown is owned by scripts/cleanup-worktrees.sh at end-of-feature.
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
  local override
  override=$(yq ".stories[] | select(.id == \"$sid\") | .override // []" "$MANIFEST")
  if echo "$override" | grep -q 'large-diff-ok'; then
    return 0
  fi
  local branch files lines
  branch=$(story_branch_name "$sid")
  files=$(git -C "$REPO_ROOT/$wt" diff --name-only "$INTEGRATION_BRANCH..$branch" | wc -l)
  lines=$(git -C "$REPO_ROOT/$wt" diff --shortstat "$INTEGRATION_BRANCH..$branch" \
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
  dirty=$(git -C "$REPO_ROOT/$wt" status --porcelain | head -1)
  if [ -n "$dirty" ]; then
    echo "worktree has uncommitted changes: '$dirty'"
    return 1
  fi
}

run_gates() {
  # $1 wt, $2 sid, $3 run-num, $4 claude-exit-code.
  # Echoes empty on success; otherwise echoes the first failed gate's reason.
  local wt="$1" sid="$2" n="$3" rc="$4"
  if [ "$rc" -ne 0 ]; then
    echo "claude exited rc=$rc (likely wall-clock kill or uncaught error)"
    return 1
  fi
  local reason
  reason=$(gate_commits_exist "$wt" "$sid")              || { echo "$reason"; return 1; }
  reason=$(gate_commit_messages_reference_story "$wt" "$sid") || { echo "$reason"; return 1; }
  reason=$(gate_diff_within_caps "$wt" "$sid")           || { echo "$reason"; return 1; }
  reason=$(gate_run_log_present "$wt" "$sid" "$n")       || { echo "$reason"; return 1; }
  reason=$(gate_worktree_clean "$wt")                    || { echo "$reason"; return 1; }
  return 0
}

# --- 11. spawn prompt + claude --------------------------------------------

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
  if yq ".stories[] | select(.id == \"$sid\") | .override // []" "$MANIFEST" \
       | grep -q 'large-diff-ok'; then
    override="1"
  fi
  # Leading `/implement-story` is parsed by the harness and injects the skill
  # body into the spawned model's context. The skill has disable-model-invocation,
  # so a mid-prompt mention would not load it — only the leading-token path works.
  cat <<EOF
/implement-story

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

# Stream-json formatter — ported from scripts/_inactive/run-ai-loop.sh.
# Reads claude's per-event JSONL on stdin, emits one human-readable line
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

spawn_claude() {
  # $1 sid, $2 prompt-file, $3 run-num. Returns claude's exit code.
  local sid="$1" prompt_file="$2" n="$3" wt rc stream_log
  wt=$(worktree_path "$sid")
  stream_log="$REPO_ROOT/$wt/$(story_runs_dir "$sid")/run-$n.stream.jsonl"
  mkdir -p "$(dirname "$stream_log")"
  log "spawning claude in $wt (run $n, stream-log: $stream_log)"

  rc=0
  ( cd "$REPO_ROOT/$wt" \
    && timeout "$PER_STORY_WALL_CLOCK" claude --permission-mode "$PERMISSION_MODE" \
         -p --output-format stream-json --verbose \
         < "$prompt_file" ) \
    | tee "$stream_log" \
    | stream_format \
    || rc=$?
  log "claude exited rc=$rc"
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

  pr_num=$(gh pr create -R "$GH_REPO" --base "$INTEGRATION_BRANCH" --head "$branch" \
             --title "$title" --body "$body" 2>/dev/null \
           | grep -oE 'pull/[0-9]+' | head -1 | sed 's|pull/||') \
    || { log "gh pr create failed for $branch"; return 1; }

  if [ -z "$pr_num" ]; then
    log "gh pr create did not return a PR number for $branch"
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

  body=$(printf '## [Type: %s | by: scripts/run-ai-loop.sh | run %s]\n\n%s' \
           "$COMMENT_TYPE_RUN_SUMMARY" "$n" "$(cat "$run_log")")
  gh pr comment "$pr" -R "$GH_REPO" --body "$body" >/dev/null \
    || { log "gh pr comment failed for PR #$pr"; return 1; }
  log "run-summary posted on PR #$pr (run $n)"
}

post_diagnostics_comment() {
  # $1 sid, $2 run-num, $3 reason
  local sid="$1" n="$2" reason="$3" pr body
  pr=$(manifest_story_field "$sid" pr)
  pr_exists "$pr" || return 0   # no PR to comment on
  body=$(cat <<EOF
## [Type: $COMMENT_TYPE_DIAGNOSTICS | by: scripts/run-ai-loop.sh | run $n]

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
  gh pr comment "$pr" -R "$GH_REPO" --body "$body" >/dev/null || true
}

# --- 13. iteration body -----------------------------------------------------

# Reconcile pr-open stories: detect merges, flip done, cleanup.
sync_remote() {
  log "sync: git fetch + reconcile pr-open stories"
  git fetch origin "$INTEGRATION_BRANCH" 2>/dev/null || true
  # Fast-forward pull only.
  git pull --ff-only origin "$INTEGRATION_BRANCH" 2>/dev/null || true

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
  propagate_runs_dir "$sid"

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
  spawn_claude "$sid" "$prompt_file" "$n" || rc=$?

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
    log "no eligible work — sleeping ${WATCH_INTERVAL}s (--watch)"
    sleep "$WATCH_INTERVAL"
  done
}

main_loop
log "runner exiting; feature=$FEATURE_SLUG"
