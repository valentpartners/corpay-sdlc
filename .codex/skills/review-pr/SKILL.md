---
name: review-pr
description: Read a Bitbucket PR — diff, commits, activities, and comments — and prepare or post review feedback.
disable-model-invocation: true
---

## Main Purpose
Read and review a Bitbucket Server/DC PR for the repository configured in `.codex/aisdlc.json`. Resolve to a numeric PR id once, then work from it. Use `BITBUCKET_API_TOKEN` from the environment or Codex config.

## Process

### 1. Resolve the PR number
- URL or explicit id → extract the numeric pull request id.
- Branch name → list open PRs in Bitbucket and match `fromRef.displayId` / `fromRef.id`.
- No input → list open PRs and pick from the list with the human.

### 2. Fetch the diff and metadata
- Read PR metadata from `/rest/api/latest/projects/{projectKey}/repos/{repoSlug}/pull-requests/{id}`.
- Read changed files from `/pull-requests/{id}/changes`.
- Read the unified diff from `/pull-requests/{id}/diff`.

### 3. Read existing threads
- Prefer the Bitbucket MCP when available for comments and activities.
- Otherwise read `/pull-requests/{id}/activities?limit=100` and paginate with `nextPageStart`.
- Honour existing thread state; don't reopen a resolved thread without the human asking.

### 4. Post a comment

**PR-level** — top-level Bitbucket PR comment:
```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $BITBUCKET_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg text "$body" '{text: $text}')" \
  "$BITBUCKET_BASE_URL/rest/api/latest/projects/$PROJECT_KEY/repos/$REPO_SLUG/pull-requests/$PR_ID/comments"
```

For inline comments, use the Bitbucket UI unless the exact anchor payload has been verified against the current diff. Bad anchors create confusing or orphaned comments.

## Rules

- **Work from the numeric id.** Never compose API calls against an unparsed URL or branch name.
- **Batch logically.** One comment per thread, not one per finding.
- **Don't post on a PR targeting `branches.protected`** without explicit go-ahead — that's typically the integration → protected merge PR.
