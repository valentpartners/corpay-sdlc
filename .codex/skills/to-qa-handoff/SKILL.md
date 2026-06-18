---
name: to-qa-handoff
description: Synthesize the feature doc's product-behavior, the manifest, and per-story testing records into a page-organized QA distribution doc at docs/ai-runs/{slug}/qa-handoff.md.
disable-model-invocation: true
---

## Main Purpose
Synthesize the feature doc's `<product-behavior>` Flows, the manifest, and per-story `testing.md` files into a page-organized QA distribution doc at `docs/ai-runs/{feature-slug}/qa-handoff.md`. Grouped by user-facing route, not by story — pages match QA's mental model.

## Process

### 1. Locate the feature
Resolve the feature slug from the optional arg; no-arg picks the most recent feature whose stories are all `done` or `wontfix`. Confirm:
- Feature doc exists at `docs/features/{slug}.md`.
- Manifest exists at `docs/ai-runs/{slug}/manifest.yaml`.
- Every story is `done` or `wontfix`. If any story is in another state, refuse — testing isn't complete.
- Per-story `testing.md` files exist at `docs/ai-runs/{slug}/{story-id}/testing.md` for each `done` story. If any are missing, the cleanup script likely hasn't run yet — refuse and tell the human to run `scripts/cleanup-codex-worktrees.sh` first.

### 2. Read the inputs
- Feature doc — parse `<product-behavior>`: Flows (`### Flow N: ...`) and R-bullets within each.
- Manifest — for each `done` story collect `id`, `title`, `validation`, `touches`; for each `wontfix` slice collect the reason.
- Per-story `testing.md` — AFK flows + results, HITL prompts narrated to the human, captured feedback during the walk.

Delegate codebase tracing of routes / pages touched to an **Explore** subagent. Goal: map the feature's user-facing surface into a page inventory.

### 3. Build the page inventory
Group the work by user-facing route. Per page:
- Route + label (e.g., `/orders/new — New Order`).
- R-bullets from `<product-behavior>` that apply to this page.
- Interactions (enter / toggle / click) drawn from validation bullets and `testing.md` HITL prompts.
- Expected outcomes per interaction.

A single story may contribute to multiple pages; a page may aggregate behavior from multiple stories. Story granularity is deliberately dropped — QA cares what to click, not which story shipped what.

### 4. Build the scenario inventory
Extract named end-to-end journeys that cross pages — e.g., "Place a first order as a new customer." Pull from feature-doc Flows that span multiple routes and from `testing.md` prompts that walked multi-page paths. Step-by-step navigation, observable result at each step.

### 5. Draft the doc
Write `docs/ai-runs/{slug}/qa-handoff.md` per [qa-handoff-template.md](qa-handoff-template.md).

### 6. Iterate with the human
Chat is the iteration surface; the doc is the sealed output. Walk the human through the page inventory, scenario list, and known limitations. Update inline as they push back. Re-runs synthesize fresh from inputs — the doc plateaus, it doesn't grow.

### 7. Exit
Tell the human: "QA handoff doc sealed at `docs/ai-runs/{slug}/qa-handoff.md`. Reference it in the integration → protected-branch PR description for downstream QA distribution."

## Rules

- **Every R-bullet maps to at least one page section.** No silently dropped behavior.
- **Every `wontfix` slice lands under "Out of scope / known limitations"** with its manifest reason.
- **Page-by-page only.** Never organize the doc by story — QA's mental model is routes, not slices.
- **Read-only on inputs.** Does not modify the feature doc, manifest, or per-story `testing.md`.
- **No PR actions.** Does not open or gate the integration → protected-branch PR; humans drive that.
- **No test execution.** AFK was already done per-story by the testing phase; results are inputs here, not actions to repeat.
- **Refuse on incomplete inputs.** Pre-`done` story → refuse. Missing `testing.md` files in the integration tree → refuse and point to `scripts/cleanup-codex-worktrees.sh`.
