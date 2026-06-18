---
name: test
description: Discover and run Deals monorepo tests.
---

## Main Purpose

Run the relevant test suite for Deals changes in the Corpay monorepo. This support repo does not contain the application test projects.

## Preconditions

- Work from the Corpay monorepo under `code/` when invoked from the AISDLC support repo.
- Scope tests to the story's touched Deals microfrontend, BFF, Domain services, and any shared contracts.
- Use legacy tests as behavioral evidence when they exist, but do not change legacy code unless the story asks for it.

## Discovery

1. Confirm the current directory is the Corpay monorepo. If invoked from the AISDLC support repo, use `code/` as the monorepo path. If neither the current directory nor `code/` is the Corpay monorepo, stop and ask for the path.
2. Inspect:
   - `package.json` scripts for frontend/unit/component tests.
   - `.sln`, `.csproj`, and test project naming for .NET tests.
   - Existing CI/pipeline commands.
   - Story implementation notes for required validation.
3. Choose the narrowest meaningful test command first, then broader tests if risk or shared behavior warrants it.

## Run

- For .NET, prefer the documented command; otherwise use `dotnet test` on the relevant solution or test project.
- For React/TypeScript, prefer the package script and package manager used by the repo.
- Run from the documented root or owning project directory.

## Report

Summarize commands, working directories, pass/fail result, and key failures. If no reliable test command can be discovered, state what was inspected and ask for the missing command.
