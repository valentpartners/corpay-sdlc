# Feature doc template

Body shape for feature docs at `docs/features/{slug}.md`. Top-down, durable to less durable. Omit empty sections.

```markdown
# {Feature name}

<problem-intent>

{What we're solving and for whom. 1–3 paragraphs. Why this work exists; who is
affected; what the current state is that we're changing.}

</problem-intent>

<scope>

{Explicit boundaries. Bulleted under **In scope** and **Out of scope** headings.
Out-of-scope items get a one-line *why*.}

</scope>

<product-behavior>

{User-perceivable behavior — what the product does, in user terms, agnostic of
implementation.}

### Flow N: {short verb phrase}

{Brief framing (1–2 sentences, optional).}

- R{n}: {user-perceivable behavior statement, written in product terms}
- R{n}: ...

#### Decisions (ONLY when a non-obvious product call was made)

- D{n}: {decision}. **Why:** {short reason}.
  - **Alternatives:** {rejected option} — {why-not}.

</product-behavior>

<architecture>

{Decisions live next to the layer they affect. Conceptual depth: artifacts
named, signatures not.}

### {Layer or area}

{Decisions in this layer.}

- D{n}: {decision}. **Why:** ...
  - **Alternatives:** ...

</architecture>

<codebase-findings>

{Existing-code claims only — grep-verifiable. Forward-looking shapes belong in
Architecture, not here.}

- {path or symbol} — what we found and why it matters.

</codebase-findings>
```
