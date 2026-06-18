---
name: build
description: Discover and run the Deals monorepo build commands.
---

## Main Purpose

Build the Deals implementation from the Corpay monorepo. This support repo does not contain the application projects.

## Preconditions

- Work from the Corpay monorepo under `code/` when invoked from the AISDLC support repo.
- Identify the relevant Deals microfrontend, BFF, Domain services, and legacy reference project paths before running commands.
- Do not invent build commands. Prefer repo scripts, solution files, project files, and existing docs.

## Discovery

1. Confirm the current directory is the Corpay monorepo. If invoked from the AISDLC support repo, use `code/` as the monorepo path. If neither the current directory nor `code/` is the Corpay monorepo, stop and ask for the path.
2. Inspect build clues:
   - `package.json` files and `scripts` entries.
   - `.sln`, `.slnx`, `.csproj`, `Directory.Build.props`, `global.json`.
   - README, build docs, pipeline files, and existing developer scripts.
3. Determine which projects are in scope for the current story:
   - Deals microfrontend.
   - BFF layer.
   - Domain services.
   - Legacy Deals application only as a reference unless the story explicitly changes it.

## Run

- For .NET projects, prefer the repo's documented build command; otherwise use the narrowest applicable `dotnet build` on the discovered solution or project.
- For React/TypeScript projects, prefer the package script that clearly builds the Deals app, such as `npm run build`, `yarn build`, or `pnpm build`, based on the repo's lockfile and scripts.
- Run commands from the owning project directory unless the monorepo documents a root command.

## Report

Summarize the command, working directory, result, and any follow-up failures. If command discovery is ambiguous, stop with the candidate commands and ask for confirmation.
