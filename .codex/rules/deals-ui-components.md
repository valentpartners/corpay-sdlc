---
paths:
  - "^code/Camtrade\\.Portal\\.UI/deals/src/Components/.*\\.(ts|tsx|js|jsx)$"
---

# Deals UI Components

Use this rule for Deals React components under `code/Camtrade.Portal.UI/deals/src/Components/`.

## Guidance

- Major UI components should expose stable `data-testid` attributes to support automated Playwright selection.
- Add `data-testid` values to primary page regions, panels, grids, forms, modals, tabs, toolbars, and action controls that tests are likely to locate directly.
- Prefer meaningful, stable names tied to the user-visible domain or workflow rather than implementation details.
- Keep test IDs stable across markup refactors unless the user-facing concept changes.

## Discovery Prompts

- Which Playwright flow would need to locate this component or control?
- Is the selector naming a business concept that should survive layout and component refactors?
