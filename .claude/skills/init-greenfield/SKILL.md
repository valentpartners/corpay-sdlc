---
name: init-greenfield
description: Specialize a fresh AISDLC scaffold — interview the project lead for the basics, fill CLAUDE.md / README.md, activate the dev-command skills, wire the workflow config, and check the dev environment.
disable-model-invocation: true
---

## Main Purpose
Turn a freshly-cloned scaffold into a project ready to start design work. Capture only the basics — a one-liner, the stack, the tracker, the dev commands — then wire those answers through every templated file. This runs **once**. Architecture, domain glossary, and ADRs are deliberately out of scope; they belong to the design phase, not here.

Be opinionated. For each question give a recommendation and a default. Ask one question at a time. Never force the lead to flesh out the product idea — the goal is the minimum needed to start, not a finished spec.

## Process

### 0. Bail if already initialized
Read `CLAUDE.md`. If the greenfield marker line (the `_Greenfield. Run `/init-greenfield` …_` italic line under *Project orientation*) is **gone**, the scaffold is already specialized. Stop. Tell the lead the project is already initialized and that revisions are direct edits to the files — this skill does not re-run.

### 1. Phase A — project basics (interview)
Ask one question at a time, walking down the logical decision tree until you feel we have reached a shared understanding. If you can provide a recommendation, do so. Do not use the AskUserQuestion UI.

1. **One-liner** — what will this project do, in a sentence or two? Not a spec.
2. **Stack** — language(s), runtime, framework(s), datastore. The load-bearing answer; everything below cascades from it. Get opinionated: propose conventional choices for the kind of project described rather than making the lead justify each one.
3. **Tracker** — where do work items live? GitHub Issues / Linear / Jira / none-yet.
4. **Dev commands** — install, run, test, build, lint, deploy. **Infer from the stack** and propose defaults (e.g. Node → `npm ci` / `npm run dev` / `npm test`); the lead confirms or corrects. A command that genuinely doesn't apply (no build step, no deploy target yet) is a valid answer — note it absent.

### 2. Phase B — workflow config
Confirm, don't grill.

1. **`branches.protected`** — the branches the runner refuses to run from or open PRs against. Default `["main","master","stage","production"]`. Confirm against the project's real branch model and its eventual integration→protected ship target; correct the list if the project uses e.g. `develop` or has no `stage`. **Getting this wrong is the one dangerous mistake** — it gates the runner away from protected branches.
2. **`branches.prefix`** — confirm `claude/` or change.
3. Leave `caps`, `paths`, `commentTypes`, `runner.permissionMode` at their defaults. State that in one line; tuning them before any story exists is guesswork.

### 3. Write the scaffolding
Apply every answer:

- **`CLAUDE.md`** — fill *What this project is* (one-liner), *Stack*, *Tracker*. Remove the greenfield marker line. Leave *Project-specific guidance* empty unless something concrete surfaced.
- **`README.md`** — fill the project name, *What it does* (human-facing, bullet-first), *Getting started* (clone → `bash scripts/setup-dev.sh` → the dev commands), *Development* (the per-command summary).
- **Dev-command skills** — for each command that applies, promote its stub: `git mv .claude/skills/_inactive/<name> .claude/skills/<name>` and replace the `{TBD}` lines with the real commands and preconditions. Leave non-applicable stubs in `_inactive/`.
- **`.claude/aisdlc.json`** — write the confirmed `branches.protected` and `branches.prefix`.
- **`.claude/settings.json`** — add `permissions.allow` entries for the stack's commands (e.g. `Bash(npm *)`, `Bash(pytest *)`). Propose a hook only if the stack has an obvious one (e.g. format-on-edit); don't invent one.
- **`scripts/setup-dev.sh`** — append the stack's setup below the `# --- stack-specific (managed by init-greenfield) ---` marker: runtime/toolchain install + version checks + dependency install (e.g. `node`, `npm ci`). Match the existing `have`/`apt_install`/`MISSING`/`MANUAL` conventions so the summary still reports cleanly. Keep privileged/interactive steps as `MANUAL` entries, not auto-run.
- **`CONTEXT.md`** — seed only the domain terms that genuinely surface in the one-liner. The project's name and core nouns are its first and most load-bearing ubiquitous language. Apply the [grill-with-docs](../grill-with-docs/SKILL.md) CONTEXT.md rules: opinionated (pick one word, list aliases to avoid), one-sentence definitions, domain-specific only (no general programming concepts), keep the example dialogue. Add nothing speculative — two or three solid terms beat ten guesses. The design phase fills out the rest.

Leave untouched: `.claude/knowledge/architecture.md`, ADRs, `.claude/skills/README.md`.

### 4. Check the environment
Run `bash scripts/setup-dev.sh` in-session. The `command -v` checks work here; `sudo apt-get` installs and `gh auth login` cannot run in this context and will surface as MANUAL entries. Relay the result plainly:
- Tools confirmed present.
- For each MANUAL entry, the exact command for the lead to run in their own terminal.

### 5. Done
Report what was filled, which skills were activated, and the env state (green vs. the dev's remaining manual steps). The scaffold is now specialized and ready for design work.
