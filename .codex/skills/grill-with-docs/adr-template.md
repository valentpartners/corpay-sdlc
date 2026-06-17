# ADR template

Body shape for ADRs at `.codex/knowledge/adrs/NNNN-{slug}.md`. Numbered sequentially, never renumbered. Omit empty sections.

```markdown
# ADR {NNNN}: {Decision in one short phrase}

- **Status:** {Proposed | Accepted | Superseded by ADR {NNNN}}
- **Date:** {YYYY-MM-DD}

## Context

{The forces at play — technical, business, constraints. What made this decision necessary. Reference prior ADRs by number where relevant.}

## Decision

{What we are doing, stated as a declarative. One paragraph. No hedging.}

## Consequences

{What becomes easier, what becomes harder, what we are now committed to. Include both positive and negative downstream effects.}

## Alternatives considered

- **{Option}** — {why rejected}. Include this only when a future reader would otherwise re-propose the alternative.
```

## Rules

- **One decision per ADR.** If you find yourself writing "and also...", split.
- **Never rewrite an accepted ADR.** Author a new one and mark the old `Superseded by ADR {NNNN}`. The history is the value.
- **Number sequentially.** Next ADR number = `ls .codex/knowledge/adrs/ | wc -l` + 1, zero-padded to 4 digits.
- **Slug from the decision, not the topic.** `0007-postgres-over-dynamo.md`, not `0007-database.md`.
