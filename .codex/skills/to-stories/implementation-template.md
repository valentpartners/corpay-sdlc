# Implementation template

Body shape for `.codex/docs/ai-runs/{feature-slug}/{story-id}/implementation.md`. The working spec the Phase 2 implementation agent consumes.

```markdown
# Implementation brief — {story-id}: {title}

## Context

- **Feature doc:** [.codex/docs/features/{feature-slug}.md](../../../features/{feature-slug}.md)
- **Applicable ADRs / rules:** {list, or "none"}

Two to four short paragraphs compacting the feature-doc context relevant to *this slice*. Cover:

- **Product intent** — the user-perceivable behaviour this slice contributes and why.
- **Architectural decisions** — the load-bearing choices for this slice's layers. Name decisions, not signatures.
- **What's non-obvious or trap-laden** — anything in the doc, the ADRs, or the prior-art codebase that would mislead a careful reader.

**Cross-cutting constraints** (only those that bind this slice):

- {constraint or rule}: {what it requires}

## Implementation plan

Top-down by layer. The agent should execute this list end-to-end without going back to the feature doc. Reference codex rules where applicable.

Each bullet:

- Names the **artefact** being added or changed (file path, class, table).
- Names the **prior art** to mirror — or states "no prior art; authoring the pattern" so the agent knows it's not failing to find something.
- Names the **intent** (what this artefact does in the slice).
- States constraints (column types, return shapes) that are decided. Does NOT prescribe method signatures, DTO shapes, or DDL beyond what's load-bearing.
```
