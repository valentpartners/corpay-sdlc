# Project orientation

## What this project is

Deals is Corpay's AISDLC support repo for carrying Codex skills, context, rules, and workflow assets between this repo and the Corpay monorepo where Deals feature code is implemented.

## Stack

This repo is a portable workflow asset repo. The target implementation surface is the Deals area of the Corpay monorepo:

- Frontend: React and TypeScript microfrontend.
- Backend: .NET / C# services.
- Supporting areas: legacy Deals application as the behavioral guide, a BFF layer, and Domain services.

## Tracker

Jira.

## Key pointers

- `.codex/skills/README.md` - AISDLC workflow and skill catalog for Codex.
- `.codex/aisdlc.json` - Codex harness config (caps, paths, tags, branch naming).
- `.codex/CONTEXT.md` - domain glossary.
- `.codex/knowledge/` - ADRs and architecture notes.

## Project-specific guidance

- Treat this repository as the source of portable AISDLC assets, not as the application monorepo.
- Copy Codex skills, context, rules, and workflow artifacts between this repo and the Corpay monorepo as needed for Deals development.
- Run build, test, lint, and local app commands from the Corpay monorepo after discovering the correct project paths and scripts there.
- Use the legacy Deals application as the behavioral reference while rebuilding the feature as a new microfrontend.
- Expect most feature work to involve the Deals microfrontend, the BFF layer, and Domain services.
