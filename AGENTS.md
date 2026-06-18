# Project orientation

## What this project is

Deals is Corpay's AISDLC support repo for carrying Codex skills, context, rules, and workflow assets while the Corpay monorepo is checked out locally under `code/`.

## Stack

This repo is a workflow harness repo. The target implementation surface is the Deals area of the nested Corpay monorepo at `code/`:

- Frontend: React and TypeScript microfrontend.
- Backend: .NET / C# services.
- Supporting areas: legacy Deals application as the behavioral guide, a BFF layer, and Domain services.

## Tracker

Jira.

## Key pointers

- `.codex/skills/README.md` - AISDLC workflow and skill catalog for Codex.
- `.codex/aisdlc.json` - Codex harness config (caps, paths, tags, branch naming).
- `CONTEXT.md` - domain glossary.
- `.codex/knowledge/` - ADRs and architecture notes.

## Project-specific guidance

- Treat this repository as the AISDLC harness, not as the application monorepo.
- Treat `code/` as the local Corpay monorepo checkout for Deals feature code.
- Run application git, build, test, lint, and local app commands from `code/` after discovering the correct project paths and scripts there.
- Use the legacy Deals application as the behavioral reference while rebuilding the feature as a new microfrontend.
- Expect most feature work to involve the Deals microfrontend, the BFF layer, and Domain services.
