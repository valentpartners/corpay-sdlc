---
paths:
  - "^code/Camtrade\\.Portal/BackendForFrontends/[^/]+/Services/.*\\.cs$"
  - "^code/Camtrade\\.Portal/BackendForFrontends/SharedServices/.*Service\\.cs$"
---

# BFF Services

## Guidance

- Keep service interfaces beside their implementation when following existing module style, and register new services in `code/Camtrade.Portal/Program.cs` or the module's existing service registration hook.
- Thin pass-through services are acceptable when the UI contract already matches the downstream API; do not add extra mapping or abstractions just to make the service look busier.
- When a service grows beyond pass-through behavior, keep that logic UI/workflow-shaped: request composition, response shaping, warnings/overrides, cache coordination, and multi-call orchestration.
- Preserve module-specific service semantics carefully, especially Wiretracking queue/filter dispatch and bulk action accounting such as matching, excluded, selected, processed, and skipped wire references.
- Use the existing structured service-boundary logging style for non-trivial methods, including stable identifiers, filters, and counts where they help diagnose user workflows.
- For services that mutate client or workflow state, check whether any BFF cache should be invalidated, refreshed, or left alone explicitly.

## Discovery Prompts

- Which existing service in this BFF module has the closest logging, mapping, and delegation pattern?
- Is the service doing more than logging and delegation? If so, what focused service test should cover orchestration, mapping, permissions, cache behavior, or error/empty-state handling?
