---
name: to-feature-manifest
description: Decompose a sealed feature doc into a manifest of vertical-slice stories on disk. Iterate with the human until the breakdown is shared.
disable-model-invocation: true
---

## Main Purpose
Decompose a sealed feature doc into a manifest of vertical-slice User Stories at `docs/ai-runs/{run-folder}/manifest.yaml`. Iterate with the human until the breakdown is shared.

## Process

### 1. Resolve source and branch
Read the named feature doc at `docs/features/{slug}.md`. If a manifest already exists for the same slug, load it — re-runs preserve sticky IDs and in-flight states.

Resolve the run folder and feature integration branch before drafting or writing:
- If the human names a branch in the prompt, use that exact branch.
- Otherwise run `git -C code branch --show-current` from the harness root when `code/` exists and recommend that value.
- If no current branch can be discovered, ask the human for the branch name.
- On a new manifest, ask the human to confirm or override the recommended branch before writing. Use the confirmed branch as the default run folder when it is a single path segment; if it contains `/` or `\`, ask for a filesystem-safe run folder.
- On an existing manifest, preserve `feature.branch` unless the human explicitly changes it; if it differs from the current `code/` branch, call out the mismatch and ask whether to update it.

Store the selected branch in `feature.branch`. Do not derive `feature.branch` from `feature.slug`. `feature.slug` remains the friendly feature/document slug.

### 2. Draft the slice breakdown
Stories function as tracer-bullets: each minimal, each with a user-perceivable validation surface so the human can correct course early.

Present as a numbered list. Per slice — **Title**, **Description** (one sentence), **Blocked by** (or "None"), **Covers** (`R{n}` from the feature doc), **Touches** (area tags), **Validation** (user-perceivable behaviours the test phase will verify).

### 3. Iterate with the human
Confirmation mindset. Surface real tensions — slice boundaries, missing `R{n}` coverage, predecessor errors. Do **not** re-open product or architectural decisions; if those are unsettled, hand back to `Skill(to-feature)`.

On re-run, auto-focus on any slice currently in `needs-info` first. After resolving, open up to other revisions.

One question per turn. Recommend an answer with each ask. Do not use the AskUserQuestion UI.

### 4. Write the manifest
On confirmation, write `docs/ai-runs/{run-folder}/manifest.yaml` per [manifest-template](./manifest-template.md), and print the DAG of the stories.

The runner finds the manifest by matching the current application branch to `feature.branch`, then uses the manifest's containing folder for `implementation.md`, run logs, stream logs, and QA artifacts.

Re-run semantics:
- **Sticky IDs.** Once assigned, an ID never changes. New slices get the next unused number; gaps are allowed.
- **State preservation.** Stories matched by ID keep their existing `state`. New slices get `drafted`.
- **Removed slices.** Set `state: wontfix`. Never delete the entry.
- **Warn before clobbering.** For stories whose metadata changed and whose state is past `drafted`, surface the diff to the human before writing.
