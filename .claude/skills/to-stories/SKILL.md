---
name: to-stories
description: Loop through drafted stories in the manifest. Per story, explore the codebase, surface concerns to the human, write the implementation brief, promote to ready-for-agent.
disable-model-invocation: true
---

## Main Purpose
Generate the per-story implementation plans. Loop through every `drafted` story in dependency order; per story, explore the codebase, surface every concern, write `implementation.md`, flip `drafted` → `ready-for-agent`.

The "no surprises" bar: the human should not be surprised by any downstream implementation steps. Ensure we have a shared understanding on what is getting implemented.

## Process

### 1. Locate manifest
Read `docs/ai-runs/{feature-slug}/manifest.yaml`. Build the loop order with TaskCreate: every story with `state: drafted`, predecessors first.

### 2. Per story, in sequence

#### 2a. Deep explore
Delegate to `Agent({subagent_type: "Explore", ...})` to gather everything the implementation agent will need:
- **Feature-doc context for this slice** — product intent the slice contributes; binding architectural decisions; cross-referenced ADRs.
- **Codebase verification** — concrete files, handlers/components/tables to mirror; drift from the doc's claims.
- **`.claude/rules/` bindings** — coding conventions that bind this slice; noteworthy conventions or ambiguities the human should know about.
- **Non-obvious traps** — anything in the doc, ADRs, or code that would mislead a careful reader.

#### 2b. Surface concerns to the human
Surface concerns and questions, and also confirm understanding if the plan goes beyond the shared understanding in the feature document.

One question/confirmation per turn; recommend an answer for any questions. Do not use the AskUserQuestion UI.

If a concern reveals the slice is fundamentally wrong (can't ship as one PR, depends on prior-art that doesn't exist, decomposes into two), flip the slice to `needs-info` in the manifest with a comment naming the issue, then skip to the next slice whose predecessors are still satisfiable.

#### 2c. Write `implementation.md`
Path: `docs/ai-runs/{feature-slug}/{story-id}/implementation.md`.

Body shape: [implementation-template](./implementation-template.md). Self-contained — the agent should not need to open the feature doc or the manifest when implementing the plan.

#### 2d. Promote state
Flip the story's `state` from `drafted` to `ready-for-agent` in the manifest. Save.

### 3. Exit
When no `drafted` story is eligible, report:
- Stories promoted to `ready-for-agent`.
- Stories left in `needs-info` (with reasons) — suggest re-invoking `to-feature-manifest`.
- Stories still `drafted` because their predecessors are `needs-info` (transitively blocked).