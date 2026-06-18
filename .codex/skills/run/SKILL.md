---
name: run
description: Discover how to start the Deals local development environment.
---

## Main Purpose

Start or describe the local Deals development environment from the Corpay monorepo.

## Preconditions

- Work from the Corpay monorepo under `code/` when invoked from the AISDLC support repo.
- Identify which surfaces are needed for the current story: Deals microfrontend, BFF layer, Domain services, and any legacy reference app.
- Do not start long-running services unless the user wants the environment booted.

## Discovery

1. Confirm the current directory is the Corpay monorepo. If invoked from the AISDLC support repo, use `code/` as the monorepo path. If neither the current directory nor `code/` is the Corpay monorepo, stop and ask for the path.
2. Inspect:
   - README or local setup docs.
   - `package.json` scripts for dev/start commands.
   - .NET launch profiles, solution files, project files, Docker Compose files, and service scripts.
   - Port and environment variable documentation.
3. Determine startup order and dependencies for the current story.

## Run

- Prefer documented scripts over direct framework commands.
- When starting long-running processes, report URLs, ports, PIDs, log locations, and stop commands.
- If auth, secrets, VPN, or local services are missing, stop with the exact missing precondition.

## Report

Summarize what was started, how to reach it, how to stop it, and what remains manual. If startup commands are ambiguous, ask before launching.
