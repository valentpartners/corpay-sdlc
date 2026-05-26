---
name: review-pr
description: Read a GitHub PR — diff, commits, threads — and post inline or PR-level comments via gh CLI.
disable-model-invocation: true
---

## Main Purpose
Read and comment on a GitHub PR via `gh`. Resolve to a numeric PR id once, then work from it. If `gh auth status` is red, refuse with the auth hint.

## Process

### 1. Resolve the PR number
- URL or branch → `gh pr view {arg} --json number,headRefName,baseRefName`.
- No input → `gh pr list --state open` and pick from the list with the human.

### 2. Fetch the diff and metadata
- `gh pr diff {number}` — full unified diff of the latest head.
- `gh pr view {number} --json files,commits,title,body,headRefOid` — file list, commits, head SHA (needed for inline comment anchoring).

### 3. Read existing threads
- `gh api repos/{owner}/{repo}/pulls/{number}/comments` — line-level review comments.
- `gh api repos/{owner}/{repo}/issues/{number}/comments` — PR-level comments.
- `gh pr view {number} --json reviews` — review summaries (APPROVE / REQUEST_CHANGES / COMMENT).

Honour existing thread state — don't reopen a resolved thread without the human asking.

### 4. Post a comment

**Inline (line-level)** — anchored to a file + line. `side=RIGHT` for added/modified, `side=LEFT` for deleted:
```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  -f body="{body}" \
  -f commit_id="{headRefOid}" \
  -f path="{file}" \
  -F line={line} \
  -f side=RIGHT
```

**PR-level** — top of the PR:
```bash
gh pr comment {number} --body "{body}"
```

If the comment is AI-generated (not human-dictated), lead the body with the [AI disclaimer](../../knowledge/shared/ai-disclaimer.md) line.

## Rules

- **Work from the numeric id.** Never compose API calls against a URL or branch name.
- **Side matters.** Wrong-side inline anchors confuse reviewers.
- **Batch logically.** One comment per thread, not one per finding.
- **Don't post on a PR targeting `branches.protected`** without explicit go-ahead — that's typically the integration → protected merge PR.
