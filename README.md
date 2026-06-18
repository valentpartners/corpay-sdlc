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
3. Run `bash scripts/setup-dev.sh` to verify the AISDLC harness tools and global monorepo toolchain.
4. Use the active command skills (`build`, `test`, `lint`, `run`) to discover and run the correct commands from the relevant Deals project paths under `code/`.

## Development

- `bash scripts/setup-dev.sh` - verifies baseline AISDLC tooling plus global `codex`, `dotnet`, `node`, and `npm` availability.
- `bash scripts/run-codex-loop.sh` - runs the AISDLC story implementation loop against the current integration branch in `code/`.
- `bash scripts/cleanup-codex-worktrees.sh` - copies back run artifacts and removes completed story worktrees.
- Dev-command skills are discovery-first because the executable project files live under `code/`, not in the harness root.

## Local Layout

- Harness assets live at this repo root: `AGENTS.md`, `.codex/`, and this README.
- Application code lives in the nested Corpay monorepo checkout at `code/`.
- `code/` is ignored by this harness repo; commit application changes using the git repo inside `code/`.
- If git reports dubious ownership for `code/`, run `git config --global --add safe.directory C:/Users/Ethan.Haugen/Documents/corpay-sdlc/code` in your terminal.

## Codex setup

- Root instructions: `AGENTS.md`.
- Workflow assets: `.codex/`, `docs/`, `scripts/`, and `CONTEXT.md`.
- Automation scripts: `scripts/`.

## Documentation

- `CONTEXT.md` - Deals glossary and domain terms.
- `.codex/skills/README.md` - AISDLC workflow and skill catalog.
- `.codex/knowledge/` - architecture notes and ADRs.
