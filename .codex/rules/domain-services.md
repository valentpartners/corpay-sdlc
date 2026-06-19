---
paths:
  - "^code/DomainServices/.*/Services/.*\\.cs$"
---

# Domain Services

Use this rule for service files in `code/DomainServices/`.

## Guidance

- Domain services are the preferred home for business rules, workflow decisions, validation beyond request shape, and coordination across repositories.
- Match the owning service's existing dependency injection, logging, validation, and result/error conventions.
- Keep persistence details behind repositories and infrastructure abstractions.
- Use legacy VB6 behavior to recover expected behavior, but express the modern rule in domain language.
- Add or update focused tests when changing business behavior.

## Discovery Prompts

- Which legacy form or workflow proves this rule?
- Which repository or downstream service provides the data?
- Which BFF or UI path depends on this behavior?
