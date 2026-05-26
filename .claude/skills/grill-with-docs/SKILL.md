---
name: grill-with-docs
description: Adversarial design dialogue that updates CONTEXT.md and proposes ADRs inline.
disable-model-invocation: true
---

## Main Purpose
Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

Keep the ask brief. For each question, give your recommendation.

Do not use the AskUserQuestion UI. Do not embed multi-part questions. If a question can be answered by exploring the codebase, use and exploration agent to save context.

## Maintain Repo Documentation

### Priority 1
Ask before updating. Update in-line.

#### Context.md
When a new domain or project-specific term is used, surface it immediately. When a term is resolved, edit [CONTEXT.md](../../../CONTEXT.md).

Rules:
- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others as aliases to avoid.
- **Keep definitions tight.** One sentence max. Define what it IS, not what it does.
- **Show relationships.** Use bold term names and express cardinality where obvious.
- **Only include terms specific to the project's domain.** General programming concepts (timeouts, error types, utility patterns) don't belong even if the project uses them extensively. Before adding a term, ask: is this concept unique to the project's domain model, or a general programming concept? Only the former belongs.
- **Group terms under subheadings** when natural clusters emerge (e.g., "Identity", "Billing", "Lifecycle"). If all terms belong to a single cohesive area, a flat list is fine.
- **Keep the example dialogue.** A realistic exchange between a dev and a domain expert demonstrates how the terms interact and clarifies boundaries between related concepts.

#### ADRs
Create a new ADR only when all three are true:
1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

What qualifies:
- **Architectural shape.** Load-bearing patterns the codebase organizes around.
- **Integration patterns.** Cross-service contracts, auth modes between systems, message-bus shapes.
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target — not every library, just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** Anything where a reasonable reader would assume the opposite.
- **Constraints not visible in the code.** Compliance requirements, partner API contracts.
- **Rejected alternatives when the rejection is non-obvious.** Otherwise someone will suggest the alternative again in six months.

Don't edit the original beyond updating its status to `Superseded by ADR XXXX`. Author a new ADR for the new decision; reference the old one in its Context. The history is the value.

### Priority 2
Update at the end of a grilling session

#### Architecture
Documentation for how something works, or patterns within the codebase are stored in [architecture.md](../../knowledge/architecture.md).

#### Coding Conventions & Rules
Specific implementation guidelines should fall within certain areas of the repo/codebase are stored in [rules/](../../rules/). Update when a particular implementation pattern is surfaced.

#### README.md Documents
README documents are not for agents. Add/Maintain them for human-level documentation and interpretability. Document workflows and overview information. Think bullets, not sentences.