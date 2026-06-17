# .codex/

Codex configuration and AISDLC workflow assets for this project.

## Layout

- `aisdlc.json` — harness config (caps, paths, tags, branch naming).
- `settings.json` — project guardrail notes; Codex runner defaults live in `aisdlc.json`.
- `skills/` — skills. See [`skills/README.md`](skills/README.md) for the AISDLC workflow + skill catalog.
- `agents/` — sub-agent definitions (e.g., `validator`, `playwright-tester`).
- `knowledge/` — ADRs, architecture notes, domain knowledge.
- `rules/` — path-scoped conventions with `paths:` frontmatter; auto-load when Codex reads a matching file.

## When you add X

- **An ADR** — `knowledge/adrs/<NNNN>-<slug>.md`, next sequential number. Use the template at [`skills/grill-with-docs/adr-template.md`](skills/grill-with-docs/adr-template.md) — it carries the rules (one-decision-per-ADR, supersession, slug-from-decision).
- **An architecture note** — `knowledge/architecture/<area>.md` when a sub-area's structure isn't obvious from a directory listing.
- **A convention** — `rules/<name>.md` with `paths:` frontmatter for auto-loading.
- **A sub-agent** — `agents/<name>.md`.
- **A new MCP server** — `.mcp.json` at repo root. Use `codex mcp --help` for Codex CLI wiring.
