---
name: write-a-skill
description: Author or revise a SKILL.md under .claude/skills/ to match this scaffold's conventions.
---

## Main Purpose
Produce a SKILL.md that is a **self-contained leaf function** — optional context in, defined job out. No workflow positioning, no "use when X" framing. Workflow lives in `.claude/skills/README.md`, not here.

Be as to-the-point as possible. Only add text if it is directly necessary for the agent to do its job when the skill is invoked.

## Process

### 1. Confirm scope
Ask: what is the single job this skill performs?

**Split when bloated, not when separable.** A 200-line skill with three loosely related sections stays one skill — lift the noisiest section to a sibling file. Split into two skills only when the trigger context differs.

### 2. Write the frontmatter
```yaml
---
name: {kebab-case, matches dir}
description: {one sentence — what the skill produces, not what it does internally}
disable-model-invocation: true  # only if the skill must be human-invoked
---
```

### 3. Write the body
Bullet-first. Sentences only for important details or emphasis. Sections in this order, omit any that don't apply:
- `## Main Purpose` — one paragraph max. Restate the job concretely.
- `## Process` — numbered steps, imperative voice. Each step is one tight paragraph or a short bullet list.

### 4. Decide what stays in SKILL.md vs. a sibling file
Lift to a sibling file when content is:
- A **template** the skill fills in (e.g., `feature-template.md` next to `to-feature`).
- **Deeper discipline** loaded only when the cadence in SKILL.md isn't enough (e.g., `tdd/{tests,mocking,refactoring}.md`).
- **Reference data** the skill consults but doesn't always need.

Reference siblings inline with a relative link: `[adr-template.md](adr-template.md)`.

## Examples to read first
- [`to-feature`](../to-feature/SKILL.md) — clean Main Purpose / Process / Rules shape; template lifted to a sibling.
- [`tdd`](../tdd/SKILL.md) — short body with multiple sibling files for progressive context.
- [`zoom-out`](../zoom-out/SKILL.md) — minimum-viable skill (7 lines). Proof that small is fine when the job is small.
- [`grill-with-docs`](../grill-with-docs/SKILL.md) — in-line documentation maintenance plus a template sibling.
