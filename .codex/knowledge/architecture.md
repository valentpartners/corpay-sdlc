# CTRI Architecture

CTRI modernizes the legacy VB6 Camtrade application into React microfrontends backed by .NET BFF and domain-service layers.

## Repository Layout

- `code/Camtrade/` - legacy VB6 application. Use `.FRM` files here as the primary behavioral reference for existing screens and workflows.
- `code/Camtrade.Portal.UI/` - modern React/TypeScript microfrontends.
- `code/Camtrade.Portal/BackendForFrontends/` - BFF layer used by the portal UI.
- `code/DomainServices/` - .NET domain services backing the modern BFF and UI.

## Workstreams

- Deals: `.codex/knowledge/architecture/deals/deals.md`
  - Frontend: `.codex/knowledge/architecture/deals/frontend.md`
  - BFF: `.codex/knowledge/architecture/deals/bff.md`
  - Domain services: `.codex/knowledge/architecture/deals/domain-services.md`
- Accounts: `.codex/knowledge/architecture/accounts/accounts.md`
  - Frontend: `.codex/knowledge/architecture/accounts/frontend.md`
  - BFF: `.codex/knowledge/architecture/accounts/bff.md`
  - Domain services: `.codex/knowledge/architecture/accounts/domain-services.md`
- Clients: `.codex/knowledge/architecture/clients/clients.md`
  - Frontend: `.codex/knowledge/architecture/clients/frontend.md`
  - BFF: `.codex/knowledge/architecture/clients/bff.md`
  - Domain services: `.codex/knowledge/architecture/clients/domain-services.md`
- Wiretracking: `.codex/knowledge/architecture/wiretracking/wiretracking.md`
  - Frontend: `.codex/knowledge/architecture/wiretracking/frontend.md`
  - BFF: `.codex/knowledge/architecture/wiretracking/bff.md`
  - Domain services: `.codex/knowledge/architecture/wiretracking/domain-services.md`
- List Functions: `.codex/knowledge/architecture/list-functions/list-functions.md`
  - Frontend: `.codex/knowledge/architecture/list-functions/frontend.md`
  - BFF: `.codex/knowledge/architecture/list-functions/bff.md`
  - Domain services: `.codex/knowledge/architecture/list-functions/domain-services.md`

Each workstream uses the same foldered architecture layout:

- `.codex/knowledge/architecture/{workstream}/{workstream}.md` - high-level domain context, cross-layer decisions, and links.
- `.codex/knowledge/architecture/{workstream}/frontend.md` - React microfrontend routes, components, generated frontend API clients, and UI conventions.
- `.codex/knowledge/architecture/{workstream}/bff.md` - portal BFF controllers, services, repositories, YAML contracts, auth, and response shaping.
- `.codex/knowledge/architecture/{workstream}/domain-services.md` - domain-service controllers, services, repositories, OpenAPI specs, persistence, and legacy integration boundaries.

Read the main `{workstream}.md` first, then read only the relevant layer files for the story.

## Modernization Pattern

Use the legacy VB6 implementation to recover behavior, not as a code-style template. Modern changes should usually land as a vertical slice through:

- a React microfrontend under `code/Camtrade.Portal.UI/<workstream>/`,
- a BFF module under `code/Camtrade.Portal/BackendForFrontends/<workstream>/` when API shaping is needed,
- one or more domain services under `code/DomainServices/` when business rules or persistence are involved.

When a story touches a workstream, update that workstream's architecture notes with the exact legacy forms, BFF endpoints, domain service files, and modern UI entry points discovered during implementation. Put cross-layer decisions in the workstream's main note, and put layer-specific details in the matching layer note when that subdivision exists.
