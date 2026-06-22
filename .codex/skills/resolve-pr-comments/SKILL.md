---
name: resolve-pr-comments
description: Address the human review comments on a Bitbucket PR — clarify ambiguous ones, change the code locally, and stop at a verified diff. Committing and any Bitbucket writes are separate, explicitly-approved steps.
disable-model-invocation: true
---

## Main Purpose
Work through the review comments on a Bitbucket Server/DC PR for the repository in `.codex/aisdlc.json`. The job ends at a verified local diff plus a summary. Committing, pushing, replying, and resolving threads are NOT part of the job — each happens only after the human approves it.

## Process

### 1. Load the PR
Use [`get-pr-from-bitbucket`](../get-pr-from-bitbucket/SKILL.md) to resolve the numeric id and fetch metadata, the unified diff, changed files, and the comment threads (with each root comment's `version`). Confirm the PR branch is checked out (`git branch --show-current`).

### 2. Triage
Separate actionable human comments from bot/automated noise (BuildAgent "All checks passed", CI status, Jira-status checks). List the actionable ones back to the human: author, location, and the ask.

### 3. Clarify ambiguous comments
For any comment with more than one reasonable resolution — refactor scope, a naming choice, a behavior change, or whether it's even in scope — ask the human before changing code. Offer a recommended option. Batch the questions; don't drip one at a time.

### 4. Change locally and verify
Make the changes, grounded in the diff and matching surrounding conventions. Run the touched area's typecheck / lint / tests. Report results honestly and distinguish pre-existing issues from anything you introduced.

### 5. Summarize and stop
Present what you addressed and how, `git diff --stat` plus key hunks, and verification results. Stop here.

### 6. Outward-facing steps — only on explicit approval, each gated separately
Load config from `.codex/aisdlc.json` as in [`get-pr-from-bitbucket`](../get-pr-from-bitbucket/SKILL.md); `$B` below is that PR's API base (`$baseUrl/rest/api/latest/projects/$P/repos/$R/pull-requests/$ID`).

- **Commit/push:** only after the human OKs the diff. Branch first if on `branches.protected`. Push to the PR branch.
- **Reply to a thread** (`$PARENT` = root comment id):
  ```bash
  curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    --data "$(jq -n --arg t "$body" --argjson p "$PARENT" '{text:$t, parent:{id:$p}}')" \
    "$B/comments"
  ```
- **Resolve a thread** (`$CID` = root comment id, `$VER` = its current `version`):
  ```bash
  curl -fsS -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    --data "$(jq -n --argjson v "$VER" '{state:"RESOLVED", version:$v}')" \
    "$B/comments/$CID"
  ```
- For inline comments, use the Bitbucket UI unless the anchor payload is verified against the current diff — bad anchors create orphaned comments.

## Rules
- **Never commit, push, reply, or resolve without explicit approval.** These are hard-to-reverse or public. The diff is yours to draft; the decision to ship it is the human's.
- **Ask, don't guess.** A wrong-but-plausible resolution wastes a review round.
- **Stay in scope.** Fix what the comment asks; note unrelated pre-existing issues instead of fixing them.
- **Don't touch threads you weren't asked about**, and don't reopen resolved ones.
- Leave a thread OPEN (reply with the plan) if the human is handling that one themselves.
