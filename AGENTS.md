# Project orientation

## What this project is

CTRI is Corpay's modernization effort for moving a legacy VB6 Camtrade application into a modern React and .NET architecture. This repo is the AISDLC harness for that work while the Corpay monorepo is checked out locally under `code/`.

## Stack

This repo is a workflow harness repo. The target implementation surface is the CTRI area of the nested Corpay monorepo at `code/`:

- Legacy reference: VB6 Camtrade application, primarily `code/Camtrade/**/*.FRM`.
- Frontend: React and TypeScript microfrontends under `code/Camtrade.Portal.UI/`.
- BFF: .NET / C# backend-for-frontend layer under `code/Camtrade.Portal/BackendForFrontends/`.
- Domain services: .NET / C# services under `code/DomainServices/`.
- Workstreams: Deals, Accounts, Clients, Wiretracking, and List Functions.

## Tracker

Jira.

## Key pointers

- `.codex/skills/README.md` - AISDLC workflow and skill catalog for Codex.
- `.codex/aisdlc.json` - Codex harness config (caps, paths, tags, branch naming).
- `CONTEXT.md` - domain glossary.
- `.codex/knowledge/architecture.md` - CTRI architecture overview.
- `.codex/knowledge/architecture/{workstream}/{workstream}.md` - workstream architecture entrypoint.
- `.codex/knowledge/architecture/{workstream}/frontend.md` - workstream frontend architecture notes.
- `.codex/knowledge/architecture/{workstream}/bff.md` - workstream BFF architecture notes.
- `.codex/knowledge/architecture/{workstream}/domain-services.md` - workstream domain-service architecture notes.
- `.codex/knowledge/architecture/deals/deals.md` - Deals workstream architecture entrypoint.
- `.codex/knowledge/architecture/accounts/accounts.md` - Accounts workstream architecture entrypoint.
- `.codex/knowledge/architecture/clients/clients.md` - Clients workstream architecture entrypoint.
- `.codex/knowledge/architecture/wiretracking/wiretracking.md` - Wiretracking workstream architecture entrypoint.
- `.codex/knowledge/architecture/list-functions/list-functions.md` - List Functions workstream architecture entrypoint.

## Project-specific guidance

- Treat this repository as the AISDLC harness, not as the application monorepo.
- Treat `code/` as the local Corpay monorepo checkout for CTRI feature code.
- Before editing or reviewing files under `code/`, check `.codex/rules/*.md`. Treat each rule file's `paths:` entries as repo-relative regex patterns over forward-slash paths; read every matching rule before making changes.
- Run application git, build, test, lint, and local app commands from `code/` after discovering the correct project paths and scripts there.
- Use legacy VB6 forms in `code/Camtrade/` as behavioral references while rebuilding features in modern microfrontends.
- Expect most feature work to involve one microfrontend under `code/Camtrade.Portal.UI/`, a BFF module under `code/Camtrade.Portal/BackendForFrontends/`, and one or more services under `code/DomainServices/`.
- When starting work in a CTRI workstream, read the matching architecture entrypoint under `.codex/knowledge/architecture/{workstream}/{workstream}.md` first, then only the layer files relevant to the story. Update the matching architecture notes as file-level ownership becomes clearer.
