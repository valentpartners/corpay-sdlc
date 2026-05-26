---
name: new-work-item
description: Append a single ad-hoc story or bug to a feature's manifest from current chat context. Single item, not a batch decomposition.
disable-model-invocation: true
---

## Main Purpose
Append one entry to `docs/ai-runs/{feature-slug}/manifest.yaml`. Pull details from the chat — don't interview the human.

## Process

### 1. Synthesise from conversation
- **Title** — verb phrase, ≤ 60 chars.
- **Type** — bug or story.
- **Description** — one or more paragraphs. For a bug: what's wrong, repro steps, expected vs actual, originating story/PR. For a story: end-to-end behaviour.
- **Validation** — user-perceivable behaviours the runner can verify (1–4 bullets).

### 2. Pick the manifest
`docs/ai-runs/{feature-slug}/manifest.yaml`. If ambiguous, ask which feature.

### 3. Pick the id
Next free `NNN-{short-slug}`. IDs are sticky; gaps are fine.

### 4. Append to `stories:`
Schema from [manifest-template.md](../to-feature-manifest/manifest-template.md):

```yaml
- id: "NNN-{slug}"
  title: {verb phrase}
  description: |
    {full context including repro for bugs}
  covers: []
  touches: [{coarse-area-tags}]
  validation:
    - {user-perceivable behaviour}
  blocked_by: []
  state: needs-info
```

Default `state: needs-info`. Use `drafted` only when validation bullets are sealed enough that `to-stories` can write `implementation.md` without further grilling.

### 5. Report
Print the new id, manifest path, and a one-line summary.

## Rules

- **Duplicate check first.** Search existing stories — near-match means ask whether to amend instead of file new.
- **Default state is `needs-info`.** Promote to `drafted` only when sealed.
- **Never set `ready-for-agent` here.** That belongs to `to-stories`.
- **Title should let a future human spot it in a list.** Vague titles are useless.
