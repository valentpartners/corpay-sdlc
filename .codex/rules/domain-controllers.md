---
paths:
  - "^code/DomainServices/.*/Controllers/.*\\.cs$"
  - "^code/DomainServices/.*\\.API/Controllers/.*\\.cs$"
---

# Domain Service Controllers

Use this rule for controller files in `code/DomainServices/`.

## Guidance

- Keep controllers focused on HTTP/API concerns: routing, request binding, auth context, status codes, and delegation.
- Put business rules in domain services, not controllers.
- Preserve existing API conventions in the owning domain service, including route shape, result models, validation style, and error handling.
- Do not change contracts used by BFF or generated clients unless the story explicitly calls for it.
- If a controller appears under a test project, use this rule only to understand the production controller contract being tested.

## Discovery Prompts

- Which BFF module or client consumes this endpoint?
- Where is request validation performed in this service?
- What service method owns the behavior behind this action?
