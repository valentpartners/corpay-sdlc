---
paths:
  - "^code/Camtrade\\.Portal/BackendForFrontends/[^/]+/Repositories/.*\\.cs$"
---

# BFF Repositories

Use this rule for repository files in the Camtrade Portal BFF layer.

## Guidance

- Keep repositories focused on data access or external-service access patterns already established in the BFF module.
- Do not put UI workflow decisions or business rules in repositories.
- Prefer existing connection, query, mapping, retry, and error-handling patterns in the same module.
- If persistence logic looks durable or domain-owned, check whether it belongs in a domain service repository instead.

## Discovery Prompts

- What data source or downstream service does this repository abstract?
- Is the repository module-local glue, or is it duplicating a domain service responsibility?
- Are there existing queries/mappers nearby that should be reused?
