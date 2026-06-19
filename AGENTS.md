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
- `.codex/knowledge/architecture/deals.md` - Deals workstream architecture notes.
- `.codex/knowledge/architecture/accounts.md` - Accounts workstream architecture notes.
- `.codex/knowledge/architecture/clients.md` - Clients workstream architecture notes.
- `.codex/knowledge/architecture/wiretracking.md` - Wiretracking workstream architecture notes.
- `.codex/knowledge/architecture/list-functions.md` - List Functions workstream architecture notes.

## Project-specific guidance

- Treat this repository as the AISDLC harness, not as the application monorepo.
- Treat `code/` as the local Corpay monorepo checkout for CTRI feature code.
- Before editing or reviewing files under `code/`, check `.codex/rules/*.md`. Treat each rule file's `paths:` entries as repo-relative regex patterns over forward-slash paths; read every matching rule before making changes.
- Run application git, build, test, lint, and local app commands from `code/` after discovering the correct project paths and scripts there.
- Use legacy VB6 forms in `code/Camtrade/` as behavioral references while rebuilding features in modern microfrontends.
- Expect most feature work to involve one microfrontend under `code/Camtrade.Portal.UI/`, a BFF module under `code/Camtrade.Portal/BackendForFrontends/`, and one or more services under `code/DomainServices/`.
- When starting work in a CTRI workstream, read the matching architecture note under `.codex/knowledge/architecture/` first and update it as file-level ownership becomes clearer.
