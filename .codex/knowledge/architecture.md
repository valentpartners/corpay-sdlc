# CTRI Architecture

CTRI modernizes the legacy VB6 Camtrade application into React microfrontends backed by .NET BFF and domain-service layers.

## Repository Layout

- `code/Camtrade/` - legacy VB6 application. Use `.FRM` files here as the primary behavioral reference for existing screens and workflows.
- `code/Camtrade.Portal.UI/` - modern React/TypeScript microfrontends.
- `code/Camtrade.Portal/BackendForFrontends/` - BFF layer used by the portal UI.
- `code/DomainServices/` - .NET domain services backing the modern BFF and UI.

## Workstreams

- Deals: `.codex/knowledge/architecture/deals.md`
- Accounts: `.codex/knowledge/architecture/accounts.md`
- Clients: `.codex/knowledge/architecture/clients.md`
- Wiretracking: `.codex/knowledge/architecture/wiretracking.md`
- List Functions: `.codex/knowledge/architecture/list-functions.md`

## Modernization Pattern

Use the legacy VB6 implementation to recover behavior, not as a code-style template. Modern changes should usually land as a vertical slice through:

- a React microfrontend under `code/Camtrade.Portal.UI/<workstream>/`,
- a BFF module under `code/Camtrade.Portal/BackendForFrontends/<workstream>/` when API shaping is needed,
- one or more domain services under `code/DomainServices/` when business rules or persistence are involved.

When a story touches a workstream, update that workstream's architecture note with the exact legacy forms, BFF endpoints, domain service files, and modern UI entry points discovered during implementation.
