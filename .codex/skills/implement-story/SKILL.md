---
name: implement-story
description: Implement one story end-to-end from its on-disk brief. Ground, vertical-slice TDD, leave app changes for the harness to commit, write the run log.
disable-model-invocation: true
---

## Main Purpose

Implement the plan described in the local `implementation.md`. Stay inside the worktree. All edits, builds, and validation stay local. Do not stage, commit, push, update refs, open PRs, or post comments; the runner owns Git staging, commits, pushes, PRs, and remote comments after you exit.

## Process

### 1. Ground

Based on `implementation.md` at the path the spawn prompt names, spawn `Agent(Explore, ...)` against the files, handlers, and components the brief references. Confirm they exist where stated; skim the prior art the brief points at. Return a short summary.

If a referenced path doesn't exist, stop and report — the brief has drifted. Recovery is `Skill(to-stories)` from the main tree.

### 2. Pick change boundaries

Decompose the story into logical units. Implement and validate one unit at a time, in order. The runner will package the final application diff into the story commit after you exit.

### 3. Per logical unit

#### 3a. Red → green per unit

One test → one implementation. Never bulk tests first.

- **Red.** Write the failing test(s) that pin this unit's behavior. Confirm they fail via `Agent(validator, ...)`.
- **Green.** Minimum code to pass. No surrounding cleanup, no speculative features. Re-run validator.
- **Refactor.** Only after green. Never while red.

Stop cleanly when you hit the TDD attempt cap from the spawn prompt — leave the run log honest about which unit failed, the last red assertion, and what you tried.

`Skill(tdd)` has the deeper discipline (anti-patterns, testability heuristics, refactor candidates) — load only if the cadence above isn't enough.

#### 3b. Leave changes for the harness

Do not run `git add`, `git commit`, `git commit-tree`, `git update-ref`, `git push`, or PR/comment commands. Leave application changes unstaged and uncommitted. The harness will commit app-code changes with the story ID in the message, or mark verification-only no-code stories done without a PR.

### 4. Write the run log

Write to the `run-<n>.md` path the spawn prompt names. The harness reposts this verbatim as the PR comment — write for both audiences.

```markdown
# Run <n>

## Summary
- <what shipped this iteration; user-perceivable change if any>
- <anything the human should check during testing>

## Detail
- **Files touched** (by area).
- **Tests added / modified.**
- **TDD cycle log** — red → green steps actually run.
- **Decisions** made beyond what the brief prescribed.
- **Open questions** for the next iteration, if any.
```

Then exit.
