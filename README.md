# Deals AISDLC Support

Codex-ready AISDLC assets for Deals development at Corpay.

## What it does

- Carries Codex skills, context, rules, and workflow assets for Deals work.
- Supports rebuilding legacy Deals functionality as a new React/TypeScript microfrontend.
- Keeps the legacy application available as the behavioral guide while feature code lands in the Corpay monorepo.
- Frames development around the Deals microfrontend, BFF layer, and Domain services.

## Getting started

1. Clone this repo.
2. Run `bash scripts/setup-dev.sh` to verify the AISDLC harness tools and global monorepo toolchain.
3. Copy the needed `.codex/`, `AGENTS.md`, `CONTEXT.md`, docs, or rules into the Corpay monorepo worktree for active Deals feature work.
4. In the monorepo, use the active command skills (`build`, `test`, `lint`, `run`) to discover and run the correct commands from the relevant Deals project paths.

## Development

- `bash scripts/setup-dev.sh` - verifies baseline AISDLC tooling plus global `codex`, `dotnet`, `node`, and `npm` availability.
- `bash scripts/run-codex-loop.sh` - runs the AISDLC story implementation loop from an integration branch.
- `bash scripts/cleanup-codex-worktrees.sh` - copies back run artifacts and removes completed story worktrees.
- Dev-command skills are discovery-first because the executable project files live in the Corpay monorepo, not in this support repo.

## Codex setup

- Root instructions: `AGENTS.md`.
- Workflow assets: `.codex/`.
- Automation scripts: `scripts/run-codex-loop.sh` and `scripts/cleanup-codex-worktrees.sh`.

## Documentation

- `CONTEXT.md` - Deals glossary and domain terms.
- `.codex/skills/README.md` - AISDLC workflow and skill catalog.
- `.codex/knowledge/` - architecture notes and ADRs.
