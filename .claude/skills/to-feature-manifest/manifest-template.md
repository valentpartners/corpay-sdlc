# Manifest template

Body shape for the manifest at `docs/ai-runs/{feature-slug}/manifest.yaml`. One file per feature.

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
- **state** — one of `tags.state` in [`.claude/aisdlc.json`](../../aisdlc.json).

The worktree branch for a story is `{branches.prefix}{id}` from `aisdlc.json` — derived, not stored.
