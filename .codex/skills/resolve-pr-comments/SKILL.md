---
name: resolve-pr-comments
description: Address the human review comments on a Bitbucket PR — clarify ambiguous ones, change the code locally, and stop at a verified diff. Committing and any Bitbucket writes are separate, explicitly-approved steps.
disable-model-invocation: true
---

## Main Purpose
Work through the review comments on a Bitbucket Server/DC PR for the repository in `.codex/aisdlc.json`. The job ends at a verified local diff plus a summary. Committing, pushing, replying, and resolving threads are NOT part of the job — each happens only after the human approves it.

## Process

### 1. Resolve the PR
Resolve to a numeric PR id (URL/id, or match an open PR by branch). The branch is usually already checked out in the application repo (`repositories.application`, e.g. `code/`); confirm with `git branch --show-current`.

### 2. Read threads and diff
Use [`review-pr`](../review-pr/SKILL.md) to read PR metadata, the unified diff, and the activities/comments. For each root comment capture `id`, `state`, `severity`, `author`, `commentAnchor`, replies, and `version` (needed to resolve later).

### 3. Triage
Separate actionable human comments from bot/automated noise (BuildAgent "All checks passed", CI status, Jira-status checks). List the actionable ones back to the human: author, location, and the ask.

### 4. Clarify ambiguous comments
For any comment with more than one reasonable resolution — refactor scope, a naming choice, a behavior change, or whether it's even in scope — ask the human before changing code. Offer a recommended option. Batch the questions; don't drip one at a time.

### 5. Change locally and verify
Make the changes, matching surrounding conventions. Run the touched area's typecheck / lint / tests. Report results honestly and distinguish pre-existing issues from anything you introduced.

### 6. Summarize and stop
Present what you addressed and how, `git diff --stat` plus key hunks, and verification results. Stop here.

### 7. Outward-facing steps — only on explicit approval, each gated separately
- **Commit/push:** only after the human OKs the diff. Branch first if on `branches.protected`. Push to the PR branch.
- **Reply to a thread:** POST to `/pull-requests/{id}/comments` with `{text, parent:{id}}`.
- **Resolve a thread:** PUT `/pull-requests/{id}/comments/{commentId}` with `{state:"RESOLVED", version}` using the root comment's current `version`.

## Rules
- **Never commit, push, reply, or resolve without explicit approval.** These are hard-to-reverse or public. The diff is yours to draft; the decision to ship it is the human's.
- **Ask, don't guess.** A wrong-but-plausible resolution wastes a review round.
- **Stay in scope.** Fix what the comment asks; note unrelated pre-existing issues instead of fixing them.
- **Don't touch threads you weren't asked about**, and don't reopen resolved ones.
- Leave a thread OPEN (reply with the plan) if the human is handling that one themselves.
