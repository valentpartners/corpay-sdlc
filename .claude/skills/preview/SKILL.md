---
name: preview
description: Story-level test driver. Boots the local env, runs AFK Playwright in parallel against a dedicated test user, narrates HITL flows in chat, appends testing.md inline. One skill, one chat, in the story's worktree.
disable-model-invocation: true
---

# Preview

Story-level Phase-3 entry point. Assumes a web stack (services + portals on localhost, Playwright-driven AFK). Boot mechanics route through the generic `/build`, `/run`, `/deploy` skills (stack-specific implementations wired up during init). The test-user provisioning hook is project-specific — init or the tech lead wires it up.

Tracer-bullet design: every vertical slice has a user-visible surface, so `preview` runs for every story regardless of whether the slice looks "UI" or "backend."

## Process

### 1. Locate the story's worktree

Story branches follow `{branches.prefix}{story-id}` (from `aisdlc.json`). Worktree at `.worktrees/{story-id}/`. If missing, refuse — the runner hasn't worked on this story yet or `cleanup-worktrees.sh` already tore it down.

### 2. Boot the env (subagent A)

In the story's worktree, build and run the services + portals the story touches. Track PIDs. Invoke the project's filled-in `/build`, `/deploy`, and `/run` skills.

Provision the dedicated test user for AFK isolation (project-specific hook). User naming convention: `afk-test-{story-id}@example.com` or similar. Capture credentials for the AFK subagent.

If a port is in use, surface `EADDRINUSE` to the human and ask them to clean up — don't silently retry.

### 3. Run AFK Playwright (subagent B, parallel with step 2)

Spawn an `Explore` subagent on the diff to map: changed files → callers → user-visible flows. Cap the flow list at `caps.afk.maxFlows` (from `aisdlc.json`). Anything beyond gets surfaced inline as "X additional flows could be impacted — out of regression scope, not tested."

Hand the flow list to the `playwright-tester` subagent (defined at `.claude/agents/playwright-tester.md`). It drives a headless browser via `playwright-cli`, logged in as the dedicated test user. No test files written — throwaway DOM assertions only. Budget: `caps.afk.wallClockSec`. Returns structured pass/fail per flow with the exercised files passed through for in-scope vs pre-existing attribution.

If destructive ops on shared state are unavoidable (and isolation breaks), fall back to **sequential mode**: AFK runs before the human walks, completes its mutations, env state is reset, then preview hands off to the human. Init decides which mode applies based on whether the test-user provisioning hook is configured.

### 4. Narrate HITL flows (main chat)

From the story's `validation` bullets in the manifest + the diff trace, tell the human which flows to walk in their own browser. Surface AFK results as they land:

```
✓ login          (4.2s)
✓ create order   (6.1s)
✗ filter by tag  (assertion failed — see below)

While AFK is running, validate these HITL flows in your browser:
  1. Toast dismissal on the new-order page (visual)
  2. Cancellation modal layout (visual)
  3. Real Service Bus message published (async external)
```

Print a readout for the human's session — URLs, PIDs, kill commands:

```
Story 003-online-toggle-ui — preview env up.

APIs:    patients         http://localhost:5043   (PID 12345)
Portals: admin-portal     http://localhost:4200   (PID 12346)

When done, kill the background processes:
  kill 12345 12346
```

### 5. Iterate on findings

Per finding (AFK fail OR human observation during the walk), the human chooses one of three paths:

- **In-scope small fix** — pair with Claude in this chat; commit; push to the story branch. Hot-reload picks up the change. Loop back to step 4 with the affected flows re-verified.
- **Out of scope** — invoke `new-work-item` for a follow-up bug or story. Note it and move on.
- **Big enough to re-run the implement agent** — the human posts a PR comment on the story's PR. The runner detects post-watermark comments on its next iteration and re-spawns the agent. Preview exits without merging.

### 6. Append testing.md inline

Throughout the session, append to `docs/ai-runs/{slug}/{story-id}/testing.md` (lives inside the worktree's runs dir; gitignored; copied back to the integration tree by `cleanup-worktrees.sh` at end-of-feature). Same inline-update pattern as `grill-with-docs` — append as things happen, don't synthesize at session close, so if the chat dies the record survives.

Contents:
- Story ID + title.
- AFK flows attempted, pass/fail, failure diagnostics.
- HITL flows narrated to the human (from validation bullets + diff).
- Human feedback captured during the walk.
- Commit SHAs of any in-chat fixes.
- Out-of-scope follow-ups filed (with `new-work-item` IDs).

### 7. Exit

When the human is satisfied, they merge the story PR via the GitHub UI (or `gh pr merge`). Preview's job is done — kill the background services and exit.

The runner detects the merge on its next iteration, flips `state → done`, and leaves the worktree + local branch in place. Teardown happens at end-of-feature via `cleanup-worktrees.sh`.

## What this does not do

- **Does not open or merge the story PR.** The human merges via GitHub UI when satisfied.
- **Does not flip manifest state.** The runner flips `pr-open → done` on its next iteration after merge.
- **Does not remove the worktree.** `cleanup-worktrees.sh` handles teardown at end-of-feature.
- **Does not post a PR comment** with the test plan. The chat + `testing.md` + PR thread are the record.
- **Does not run AFK on flows it can't isolate** (shared-state destructive ops). Those become HITL prompts.
- **Does not apply DB migrations to shared environments.** Schema changes get a manual human approval before preview runs (project-specific gate).

## Common pitfalls

- **AFK and human stepping on each other.** The dedicated test user is the isolation boundary — never let AFK touch shared global state.
- **Port conflicts from a previous run.** Detect `EADDRINUSE` and surface to the human; don't silently retry on a different port.
- **Flaky AFK rows masked as fails.** Re-run a flow once before declaring fail; don't drag the human into a phantom regression.
- **Forgetting to append a finding** to `testing.md`. The file is the input to `to-qa-handoff` later — if it's not there, QA loses context.
