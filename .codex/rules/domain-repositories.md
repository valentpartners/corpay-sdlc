---
paths:
  - "^code/DomainServices/.*/Repositories/.*\\.cs$"
---

# Domain Repositories

Use this rule for repository files in `code/DomainServices/`.

## Guidance

- Keep repositories focused on persistence, query construction, data mapping, and data-source-specific concerns.
- Do not put business rules, UI shaping, or workflow branching in repositories.
- Prefer existing query, transaction, connection, mapping, and error-handling patterns in the same domain service.
- Keep repository methods named around the data operation they perform, not the UI action that triggered them.
- When changing queries, look for existing repository tests or service-level tests that cover the resulting behavior.

## Discovery Prompts

- Which service method consumes this repository method?
- Is the query reusable domain data access or story-specific shaping that belongs elsewhere?
- Does this change affect transaction boundaries, ordering, filtering, or pagination?
