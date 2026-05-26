---
name: to-qa-handoff
description: Synthesize the feature doc and per-story testing records into a page-organized QA distribution doc at docs/ai-runs/{slug}/qa-handoff.md.
disable-model-invocation: true
---

<context>

- Feature doc at `docs/features/{slug}.md` — specifically the `<product-behavior>` section's Flows + R-bullets (user-perceivable behavior).
- Manifest at `docs/ai-runs/{slug}/manifest.yaml` — story `validation` bullets and `wontfix` slices.
- Per-story testing records at `docs/ai-runs/{slug}/{story-id}/testing.md` — AFK flows + results, HITL prompts narrated to the human, captured feedback during the walk.
- `aisdlc.json` for path templates.
- *Optional context input:* a feature slug. No-arg picks the most recent feature whose stories are all `done`.

</context>

<process>

### 1. Locate the feature

Resolve the feature slug. Confirm:
- Feature doc exists at `docs/features/{slug}.md`.
- Manifest exists at `docs/ai-runs/{slug}/manifest.yaml`.
- Every story is `done` or `wontfix`. If any story is in another state, refuse — testing isn't complete.
- Per-story `testing.md` files exist under `docs/ai-runs/{slug}/{story-id}/` for each `done` story. If any are missing, the cleanup script likely hasn't run yet — refuse and tell the human to run `scripts/cleanup-worktrees.sh` first.

### 2. Read the inputs

- Feature doc — parse `<product-behavior>`: Flows (`### Flow N: ...`), R-bullets within each.
- Manifest — collect each `done` story's `id`, `title`, `validation` bullets, `touches`, and any `wontfix` slices with their reasons.
- Per-story `testing.md` — gather AFK flows + results, HITL prompts walked, human feedback captured during testing.

For codebase tracing of routes / pages touched, delegate to an **Explore** subagent. The goal is mapping the feature's user-facing surface into a page inventory.

### 3. Build the page inventory

Group the work by user-facing route, not by story. Pages match QA's mental model. For each page:

- Route + label (e.g., `/orders/new — New Order`).
- R-bullets from `<product-behavior>` that apply to this page.
- Interactions (enter / toggle / click) drawn from validation bullets and testing.md HITL prompts.
- Expected outcomes per interaction.

A single story may contribute to multiple pages; a single page may aggregate behavior from multiple stories. The doc deliberately abandons story granularity — QA cares what to click, not which story shipped what.

### 4. Build the scenario inventory

Extract named end-to-end journeys that cross pages — e.g., "Place a first order as a new customer." Pull from feature-doc Flows that span multiple routes and from testing.md prompts that walked multi-page paths. Step-by-step navigation, observable result at each step.

### 5. Draft the doc

Write `docs/ai-runs/{slug}/qa-handoff.md`.

Structure:

```markdown
# QA handoff — {Feature name}

## Prerequisites
- Test environment URL: {url}
- Test user credentials: {creds or pointer}
- Feature flags to enable: {flags, or "none"}
- Other setup: {fixtures, seed data, etc.}

## Pages

### `/route — Page label`

**On this page you should see:**
- R{n}: {behavior}
- R{n}: {behavior}

**On this page you can:**
- {interaction}
- {interaction}

**Expected outcomes:**
- {interaction → result}

### `/other-route — Other Page`
...

## End-to-end scenarios

### Scenario: {short title}
1. Navigate to `/route` — see X.
2. Click Y — should land on `/next-route`.
3. ...

## Out of scope / known limitations
- {wontfix slice} — {reason from manifest}
- {validation gap surfaced during testing}
```

### 6. Iterate with the human in chat

Chat is the iteration surface; the doc is the sealed output (same pattern as `to-feature-manifest`). Walk the human through the page inventory, scenario list, and known limitations. Update inline as they push back. Re-runs synthesize fresh from inputs — the doc plateaus, it doesn't grow.

### 7. Exit

Tell the human: "QA handoff doc sealed at `docs/ai-runs/{slug}/qa-handoff.md`. Reference it in the integration → protected-branch PR description for downstream QA distribution."

</process>

<validation>

- Every story under the feature is `done` or `wontfix` before the doc is written.
- Every R-bullet from `<product-behavior>` maps to at least one page section.
- Every `wontfix` slice appears under "Out of scope / known limitations."
- The doc lives at `docs/ai-runs/{slug}/qa-handoff.md`.

</validation>

<guardrails>

- Does not open the integration → protected-branch PR. That stays a human-driven action.
- Does not gate the merge. QA is advisory — the human decides when to ship.
- Does not modify the feature doc, manifest, or per-story `testing.md`. Read-only on inputs.
- Does not run automated tests. AFK was already done per-story by `preview`; results are inputs here, not actions.
- Does not organize by story. Page-by-page only — QA's mental model is routes, not slices.
- Does not run if any story is in a pre-`done` state. Refuse.
- Does not run if per-story `testing.md` files aren't present in the integration tree. Refuse and point to the cleanup script.

</guardrails>
