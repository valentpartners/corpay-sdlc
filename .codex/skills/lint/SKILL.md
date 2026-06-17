---
name: lint
description: Discover and run Deals monorepo lint/static analysis commands.
---

## Main Purpose

Run static analysis for Deals changes in the Corpay monorepo.

## Preconditions

- Work from the Corpay monorepo, not from the AISDLC support repo.
- Prefer the monorepo's documented lint, format-check, analyzer, or CI validation commands.
- Avoid broad formatting unless explicitly requested or clearly required by the project convention.

## Discovery

1. Confirm the current directory is the Corpay monorepo. If it is not, stop and ask for the monorepo path.
2. Inspect:
   - `package.json` scripts for `lint`, `format`, `typecheck`, or related commands.
   - ESLint, Prettier, TypeScript, Stylelint, or workspace config files.
   - .NET analyzer/format commands such as documented `dotnet format` usage.
   - CI/pipeline definitions.

## Run

- For React/TypeScript, run the discovered lint or typecheck script from the correct package/workspace.
- For .NET, run the documented analyzer/format-check command if present.
- If only auto-fix commands exist, ask before applying broad fixes.

## Report

Summarize command, working directory, result, and any remaining diagnostics. If discovery is ambiguous, present candidates instead of guessing.
