---
name: implement-simple-story
description: Implement one simple-story implementation.md locally and leave a handoff for human testing.
disable-model-invocation: true
---

## Main Purpose
Implement the local simple-story `implementation.md` on the prepared application branch. Keep changes focused, avoid runner/manifest mechanics, and leave the diff plus a run log for human testing.

## Process

### 1. Locate and read the brief
- Use the `implementation.md` path supplied by the caller.
- If no path is supplied, look under `docs/ai-runs/simple-jira/{ISSUE-KEY}/implementation.md`.
- If no brief exists, stop and run [`to-simple-story`](../to-simple-story/SKILL.md) first.

### 2. Ground before editing
- Read the brief fully.
- Load `.codex/aisdlc.json`; use `repositories.application` as the app repo path, normally `code/`.
- Confirm the application repo is on the branch named in the brief and not on `master`, `main`, `stage`, or `production`.
- If the worktree has unrelated changes, stop and ask the human how to proceed.
- Recheck referenced paths and prior art. If the brief has drifted from the codebase, stop and return to `to-simple-story`.
- Before editing any file under `code/`, read every matching `.codex/rules/*.md` rule for that forward-slash path.

### 3. Implement the plan
- Apply the smallest coherent change that satisfies the brief.
- Keep edits within the ticket scope.
- Do not do opportunistic refactors.
- Do not run build, lint, or tests unless the human explicitly asks.
- Add or update tests only when the brief explicitly names test files or the surrounding code convention makes the test edit part of the implementation.

### 4. Write the run log
- Write `docs/ai-runs/simple-jira/{ISSUE-KEY}/run.md`.
- Include:
  - summary of what changed
  - files touched
  - decisions made beyond the brief
  - open questions, if any
  - build/lint/test commands not run because the human owns testing
  - manual testing reminders
  - cleanup steps after merge

### 5. Handoff
- Report the branch, brief path, run log path, changed files, and testing reminders.
- Do not stage, commit, push, open a PR, or update Jira unless the human explicitly asks.

## Rules
- If implementation reveals a product decision that was not settled in the brief, stop and ask before coding through it.
- Do not claim verification that was not performed.
- Keep generated work records under `docs/ai-runs/simple-jira/{ISSUE-KEY}/`.
