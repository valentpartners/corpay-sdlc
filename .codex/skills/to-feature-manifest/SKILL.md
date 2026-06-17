---
name: to-feature-manifest
description: Decompose a sealed feature doc into a manifest of vertical-slice stories on disk. Iterate with the human until the breakdown is shared.
disable-model-invocation: true
---

## Main Purpose
Decompose a sealed feature doc into a manifest of vertical-slice User Stories at `.codex/docs/ai-runs/{feature-slug}/manifest.yaml`. Iterate with the human until the breakdown is shared.

## Process

### 1. Resolve source
Read the named feature doc at `.codex/docs/features/{slug}.md`. If a manifest already exists for the same slug, load it — re-runs preserve sticky IDs and in-flight states.

### 2. Draft the slice breakdown
Stories function as tracer-bullets: each minimal, each with a user-perceivable validation surface so the human can correct course early.

Present as a numbered list. Per slice — **Title**, **Description** (one sentence), **Blocked by** (or "None"), **Covers** (`R{n}` from the feature doc), **Touches** (area tags), **Validation** (user-perceivable behaviours the test phase will verify).

### 3. Iterate with the human
Confirmation mindset. Surface real tensions — slice boundaries, missing `R{n}` coverage, predecessor errors. Do **not** re-open product or architectural decisions; if those are unsettled, hand back to `Skill(to-feature)`.

On re-run, auto-focus on any slice currently in `needs-info` first. After resolving, open up to other revisions.

One question per turn. Recommend an answer with each ask. Do not use the AskUserQuestion UI.

### 4. Write the manifest
On confirmation, write `.codex/docs/ai-runs/{feature-slug}/manifest.yaml` per [manifest-template](./manifest-template.md), and print the DAG of the stories.

Re-run semantics:
- **Sticky IDs.** Once assigned, an ID never changes. New slices get the next unused number; gaps are allowed.
- **State preservation.** Stories matched by ID keep their existing `state`. New slices get `drafted`.
- **Removed slices.** Set `state: wontfix`. Never delete the entry.
- **Warn before clobbering.** For stories whose metadata changed and whose state is past `drafted`, surface the diff to the human before writing.
