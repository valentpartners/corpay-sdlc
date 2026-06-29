---
name: review-pr-aisdlc
description: Read a Bitbucket PR — diff, commits, activities, and comments — and prepare or post review feedback.
disable-model-invocation: true
---

## Main Purpose
Read and review a Bitbucket Server/DC PR for the repository configured in `.codex/aisdlc.json`. Resolve to a numeric PR id once, then work from it. Use `BITBUCKET_API_TOKEN` from the environment or Codex config.

## Process

### 1. Load the PR
Use [`get-pr-from-bitbucket`](../get-pr-from-bitbucket/SKILL.md) to resolve the numeric id and fetch metadata, changed files, the unified diff, and the comment threads. Prefer the Bitbucket MCP for comments/activities when available. Honour existing thread state; don't reopen a resolved thread without the human asking.

### 2. Post a comment

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
