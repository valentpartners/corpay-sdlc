# Manifest template

Body shape for the manifest at `docs/ai-runs/{run-folder}/manifest.yaml`. One file per feature run. The runner matches the current application branch against `feature.branch`, then uses the manifest's containing folder for story artifacts.

```yaml
feature:
  slug: {feature-slug}
  doc: docs/features/{feature-slug}.md
  branch: {human-named feature integration branch}

stories:
  - id: "001-{short-slug}"
    title: {short verb phrase}
    description: {one sentence of intent}
    covers: [R1, R2]
    touches: [area1, area2]
    validation:
      - {user-perceivable behaviour bullet}
      - {user-perceivable behaviour bullet}
    blocked_by: []
    state: drafted

  - id: "002-{short-slug}"
    title: ...
    ...
    blocked_by: ["001-{short-slug}"]
    state: drafted
```

## Field conventions

- **id** — `NNN-{short-slug}`. Sticky; never renumbered. Gaps allowed.
- **title** — short verb phrase. Becomes the worktree branch slug.
- **description** — one sentence; what the slice ships.
- **covers** — `R{n}` IDs from the feature doc. Every `R{n}` in the doc should map to at least one slice.
- **touches** — coarse area tags (e.g., `db`, `api`, `ui`). Aids human scanning + downstream filtering.
- **validation** — user-perceivable behaviours the test phase will verify. Sealed at design time; feeds Phase 3 directly.
- **blocked_by** — list of IDs whose `state` must be `done` before this slice is eligible.
- **state** — one of the structural states documented in [`.codex/skills/README.md`](../../README.md) (e.g., `drafted`, `ready-for-agent`, `agent-dev`, `pr-open`, `done`, `needs-info`, `ready-for-human`, `wontfix`).
- **feature.branch** — exact integration branch in `code/` that the runner should match. Confirm with the human or default to `git -C code branch --show-current`; do not infer it from `feature.slug`.
- **run folder** — the directory containing this manifest under `docs/ai-runs/`. It may match the integration branch when that branch is filesystem-safe. `implementation.md` and run logs live under this folder.

Optional fields:

- **override** — list, subset of `tags.override` (e.g., `[large-diff-ok]`). Human-managed; tells the runner to bypass specific caps for this slice.
- **pr** — integer PR number. Machine-managed; written by the runner when it opens the story PR. Do not hand-edit.

The worktree branch for a story is `{branches.prefix}{id}` from `aisdlc.json` — derived, not stored.
