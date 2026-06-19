# Deals AISDLC Support

Codex-ready AISDLC assets for Deals development at Corpay.

## What it does

- Carries Codex skills, context, rules, and workflow assets for Deals work.
- Supports rebuilding legacy Deals functionality as a new React/TypeScript microfrontend.
- Keeps the legacy application available as the behavioral guide while feature code lands in the nested Corpay monorepo checkout under `code/`.
- Frames development around the Deals microfrontend, BFF layer, and Domain services.

## Getting started

1. Clone this repo.
2. Clone or place the Corpay monorepo at `code/` inside this repo.
3. Run `powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1` to verify the AISDLC harness tools, Bitbucket auth, and global monorepo toolchain.
4. Use the active command skills (`build`, `test`, `lint`, `run`) to discover and run the correct commands from the relevant Deals project paths under `code/`.

## Development

- `powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1` - verifies baseline AISDLC tooling, Bitbucket REST access, and global `codex`, `dotnet`, `node`, and `npm` availability.
- `powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\run-codex-loop.ps1` - runs the AISDLC story implementation loop against the current integration branch in `code/`, opening story PRs in Bitbucket.
- `powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1` - copies back run artifacts and removes completed story worktrees.
- Dev-command skills are discovery-first because the executable project files live under `code/`, not in the harness root.

## Local Layout

- Harness assets live at this repo root: `AGENTS.md`, `.codex/`, and this README.
- Application code lives in the nested Corpay monorepo checkout at `code/`.
- `code/` is ignored by this harness repo; commit application changes using the git repo inside `code/`.
- If git reports dubious ownership for `code/`, run `git config --global --add safe.directory C:/Users/Ethan.Haugen/Documents/corpay-sdlc/code` in Windows.

## Source Control

- Story and integration PRs live in Bitbucket Server/DC at `https://bitbucket.cambridgefx.com/projects/C/repos/code`.
- Bitbucket settings are in `.codex/aisdlc.json` under `sourceControl`.
- The scripts read `BITBUCKET_API_TOKEN` from the environment or from your Codex config.
- If setup reports that Bitbucket cannot be reached, fix Windows VPN/DNS/proxy access before debugging the token.

## Codex setup

- Root instructions: `AGENTS.md`.
- Workflow assets: `.codex/`, `docs/`, `scripts/`, and `CONTEXT.md`.
- Automation scripts: `scripts/`.

## Documentation

- `CONTEXT.md` - Deals glossary and domain terms.
- `.codex/skills/README.md` - AISDLC workflow and skill catalog.
- `.codex/knowledge/` - architecture notes and ADRs.
