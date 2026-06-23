# Simple story implementation template

Body shape for `docs/ai-runs/simple-jira/{ISSUE-KEY}/implementation.md`.

```markdown
# Implementation brief - {ISSUE-KEY}: {summary}

## Ticket

- **Jira:** {url}
- **Status:** {status}
- **Type:** {issue type}
- **Assignee:** {assignee or "unassigned"}
- **Branch:** {ISSUE-KEY}-{ticket-name-slug}
- **Application repo:** code/
- **Base:** master

## Outcome

Two to four sentences describing the user-perceivable behavior this ticket should change and why.

## Scope

### In
- {specific behavior or artifact}

### Out
- {adjacent behavior explicitly left alone}

## Jira requirements

### Acceptance / requirements
- {criterion, or "Not specified in Jira."}

### Relevant comments and links
- {comment/link that changes scope, or "None."}

## Codebase grounding

- **Architecture notes read:** {files, or "none"}
- **Applicable rules:** {rules files, or "none"}
- **Prior art to mirror:** {files/classes/components/routes, or "none found"}
- **Legacy reference:** {VB6 forms/files, or "none needed"}
- **Expected files to touch:** {paths}
- **Non-obvious traps:** {short bullets, or "none found"}

## Implementation plan

Top-down by layer. Each bullet names the artifact, the prior art to mirror, the intended behavior, and constraints that are already decided.

- {artifact}: {intent, prior art, constraints}

## Human testing handoff

- {manual check the human should perform}
- Build/lint/test execution is owned by the human for this fast lane unless they explicitly ask Codex to run a command.

## Cleanup after merge

- Confirm the PR is merged.
- In `code/`, switch to `master` and update it with `git pull --ff-only origin master`.
- Confirm the ticket branch appears in `git branch --merged master`.
- Delete the local ticket branch with `git branch -d {branch}`. Do not force-delete unless explicitly asked.
- Keep this `docs/ai-runs/simple-jira/{ISSUE-KEY}/` folder unless the human asks to remove or archive it.
```
