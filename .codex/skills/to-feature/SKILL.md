---
name: to-feature
description: Synthesise product and architecture-level information from the current chat and any referenced files into a sealed feature doc.
disable-model-invocation: true
---

## Main Purpose
Synthesise product and architecture-level information from the current chat and any referenced files into a sealed feature doc.

## Process

### 1. Scope check
Signal to the user if the current feature can be broken into separate feature documents. Reasons can include:
- Two distinct user-facing capabilities with no shared flows.
- Architecture decisions cluster into disjoint sub-trees.
- Out-of-scope items read more like "next feature" than "won't do".
- Codebase findings cluster around two different parts of the codebase.

Compacting to a feature document already over 50k tokens should trigger a cluster check, but the split is only asked if the cluster signal is also present.

### 2. Determine slug
Reuse if the chat references an existing doc. Otgherwise kebab-case, 2-4 words.

### 3. Synthesize into the template
Extract settled content into its respective section within the [feature-template](./feature-template.md).

If folding into an existing doc, synthesize and replace, do not append. Surface contradictions explicitly; ask which version stands.

Guidelines:
- Product capabilities → new or extended **Flows**.
- Architectural decisions → the **Architecture** sub-section for that layer.
- Codebase observations → **Codebase findings**.
- Rejected alternatives → `Alternatives:` sub-bullet on the decision they lost to.
- Scope changes → **In / Out of scope**.
- Problem framing changes only if the chat sharpened it.
- `R{n}` and `D{n}` are globally unique across the doc.

If split into multiple feature documents: distribute flows / architecture / codebase findings. Duplicate shared decisions and findings into both — each doc must stand alone.

## Rules

- **Settled-only.** No Open Questions, no TBDs, no shaky content in the body.
- **Plateau, don't append.** No "round 2" subsection, no changelog.
- **Omit empty sections.** No headers without content.
- **Decisions live next to what they affect.** Product decisions inside flows; architecture decisions inside layers. No flat "Decisions made" section.
- **No implementation signatures.** Handler classes, route URLs, DTO types, method bodies belong downstream.
- **No References / Glossary / Status sections in the body.** References live in `CONTEXT.md` and ADRs; glossary in `CONTEXT.md`.
- **One question per turn.** Don't bundle the glossary and merge-conflict passes.
- **Never seal with open questions.** Shaky threads either resolve in conversation and become decisions, or ride the verbal handoff channel.
