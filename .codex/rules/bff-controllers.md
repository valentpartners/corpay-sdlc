---
paths:
  - "^code/Camtrade\\.Portal/BackendForFrontends/[^/]+/Controllers/.*\\.cs$"
---

# BFF Controllers

Use this rule for controller files in the Camtrade Portal BFF layer.

## Guidance

- Do not put business rules, persistence logic, or legacy-behavior reconstruction directly in controllers.
- Prefer existing route, action naming, response wrapper, logging, and error-handling conventions in the same BFF module.
- Use structured controller logs with the existing `[CTRL] Begin...` / `[CTRL] End...` style. Include useful identifiers, filters, counts, filenames, and status context.
- Reserve `LogError` for unexpected failures. Expected UI-facing outcomes such as validation failures, missing clients/records, unauthorized/forbidden responses, feature-flag blocks, and upstream 4xx responses should use `LogWarning` or `LogInformation` according to severity.
- Map expected errors to explicit UI responses such as `BadRequest`, `NotFound`, `Conflict`, `UnprocessableEntity`, `StatusCode(403)`, or `StatusCode(503)`. Return generic messages for unexpected `500` responses.
- Keep feature-flag checks near the HTTP action they gate. Return `403` when a disabled feature should block the call, log it as an expected outcome, and use the existing `CamtradePortal_*` configuration naming pattern.

## Discovery Prompts

- Is this endpoint shaping UI-specific data or exposing a domain behavior?
- Is there an existing endpoint in the same module with the same auth/error/result pattern?
