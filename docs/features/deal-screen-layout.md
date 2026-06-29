# Deal Screen Layout

<problem-intent>

Deals modernization needs the first modern Deal screen to move beyond a blank placeholder without pretending that Deal data, lookup, grids, fields, or mutations exist yet. Product and engineering need a shell structure that can be reviewed for region placement and future component boundaries before later stories wire real business behavior.

This feature establishes the Deal screen shell in the Deals microfrontend. It follows the provided Deal mockup exactly for design, density, region priority, and spatial structure, but implements only placeholder shell components in the modern React/MUI portal stack.

</problem-intent>

<scope>

**In scope**

- Replace the Deals placeholder surface with a visual Deal screen layout.
- Show Deal lookup/navigation, Deal header, comments, Buy/Sell, Settlement, Payment, and Income/Expense shell regions.
- Reserve shell space for lookup/navigation controls, top-level Deal actions, comment tabs/sections, and grid placeholder bodies.
- Match the mockup's dense workbench layout, including vertical space usage, compact header placement, grid-region contrast, and Settlement/Payment priority.
- Add local Deals shell component patterns for `DealMainPanel`, `DealPanel`, lookup/navigation, header, comments, and grid placeholders.
- Add focused frontend coverage for rendering the layout shell.

**Out of scope**

- Deal lookup execution, loading, previous/next navigation, or route changes; later data-loading work owns the Deal selection contract.
- Deal API calls, generated Deal business clients, BFF operations, domain-service operations, or mutations; this feature is UI structure only.
- Header field modeling, representative fake Deal data, field-value fallback behavior, or future Deal read-model shape.
- Real transaction columns, transaction rows, AG Grid wiring, row action menus, popouts, exports, or modals; later grid behavior stories own those interactions.
- Add/edit modals, fullscreen grid behavior, row action preservation, header persistence, and legacy validations; later behavior stories own those interactions.
- Comment tab switching, comment load, save, edit, or permissions behavior; later comment stories own persistence and authorization.
- Final Deal permission modeling beyond the existing Deals microfrontend gate; a later permissions story owns that contract.
- API, AG Grid, permission, mutation, field, transaction-column, and persisted comment tests; later behavior stories own those contracts.

</scope>

<product-behavior>

### Flow 1: View the Deal screen shell

An authorized portal user can open the Deals application and see a realistic Deal screen scaffold instead of the previous placeholder.

- R1: The Deal screen shows a lookup/navigation region with Deal #, Order #, previous, and next controls.
- R2: The Deal screen shows a Deal header shell with space for the title/identifier, future header field area, and top-level Deal actions.
- R3: Top-level Deal actions are visible as disabled controls so reviewers can inspect spacing without invoking behavior.
- R18: The shell follows `docs/mockups/frmDeal-react-mockup-v2.html` exactly for design intent instead of borrowing layout or chrome from Clients or Wiretracking.
- R19: The Deal screen shell uses the available vertical space as a dense workbench, not as a lightly populated placeholder page.
- R20: The Deal header shell is compact enough to support the mockup's collapsed one-row header direction.
- R21: Settlement and Payment regions are visually prioritized over the other transaction regions.
- R22: Grid shell regions have enough contrast from one another for reviewers to distinguish the major work areas.

#### Decisions

- D1: Render a header shell without fake Deal field values. **Why:** this story only establishes component regions, and field content belongs to a later Deal read-model story.
  - **Alternatives:** Show representative fake header fields - rejected because it creates field scope not required by the story.
- D21: Treat the mockup as the exact design contract for this shell, not merely inspiration. **Why:** product review is now comparing the Deals shell directly against the mockup.
  - **Alternatives:** Reuse Clients or Wiretracking components where convenient - rejected because their existing chrome and interaction assumptions would drift from the Deal mockup.

### Flow 2: Review comments structure

The screen reserves space for comment tabs/sections without adding comment persistence or local tab behavior.

- R4: The comments region shows tabs for Comment, Delivery, Receivable, Wires, and Related Deals.
- R5: The comments region shows a placeholder body for future comment content.
- R6: The comments region does not show saved mock comments, editable fields, or save actions.
- R7: The comments shell is rendered inside the Deal header region while remaining a separate component.

#### Decisions

- D2: Render comment tabs as shell labels for this slice. **Why:** the story asks for a comments shell, and comment behavior belongs to a later comment story.
  - **Alternatives:** Make tabs locally switch panels - rejected because it adds behavior not required by the shell story.
- D3: Compose `DealComments` inside `DealHeader` while keeping it as its own component. **Why:** the mockup places comments within the header area, but the Jira scope treats comments as a distinct shell region.
  - **Alternatives:** Render comments as a sibling below the header shell - rejected because it drifts from the mockup's spatial structure.

### Flow 3: Review transaction grid placeholders

The screen reserves each transaction grid area without modeling transaction columns or row behavior.

- R8: The Deal screen shows placeholder shells for Buy/Sell, Settlement, Payment, and Income/Expense.
- R9: Each grid placeholder has a title and placeholder body.
- R10: Transaction columns, rows, row action columns, and row action menus are not shown in this story.
- R11: Section-level grid toolbar actions from the mockup are visible as disabled controls for spacing review.
- R12: Placeholder body text is terse and label-like, not explanatory implementation copy.
- R13: Settlement and Payment placeholders span the full content width; Buy/Sell and Income/Expense share a two-column row on desktop and stack when width is constrained.

#### Decisions

- D4: Use generic placeholder bodies instead of transaction tables. **Why:** the story only asks for grid placeholders, and transaction column vocabulary belongs to later grid stories.
  - **Alternatives:** Render empty transaction tables with real mockup columns - rejected because it over-scopes this shell story.
- D5: Show section-level grid toolbar actions as disabled controls. **Why:** the layout story needs realistic toolbar spacing, while the disabled state keeps modals, exports, popouts, and mutations out of scope.
  - **Alternatives:** Omit toolbar actions completely - rejected because the reviewed layout would understate the space each grid section needs.
- D6: Use simple placeholder labels in shell bodies. **Why:** the UI should reserve space without explaining future implementation work to users.
  - **Alternatives:** Show explanatory text such as "grid behavior will be added later" - rejected because implementation context belongs in docs, not the screen.
- D7: Preserve the mockup's grid-region spans rather than using a uniform 2x2 grid. **Why:** Settlement and Payment need full-width shell space, while Buy/Sell and Income/Expense can share a row until responsive constraints require stacking.
  - **Alternatives:** Render all four grid placeholders as a uniform 2x2 grid - rejected because it does not match the provided mockup structure.

### Flow 4: Review Income/Expense placeholder

Income/Expense appears as one placeholder region.

- R14: Income/Expense appears as one shell region with a placeholder body.
- R15: Income/Expense does not implement tab switching or charge-grid behavior in this story.

#### Decisions

- D8: Keep Income/Expense as one placeholder section. **Why:** the story names one Income/Expense grid placeholder, and split tab behavior can be introduced when charge-grid behavior is defined.
  - **Alternatives:** Build local Income and Expense tabs now - rejected because it adds behavior beyond the shell.

### Flow 5: Verify layout-only behavior

The feature is verified at the same level of behavior it owns: rendering the shell.

- R16: A frontend smoke test renders the Deal screen without crashing and verifies the major layout regions are present.
- R17: The Deals frontend build still completes successfully.

#### Decisions

- D9: Add focused frontend render coverage only. **Why:** this story owns shell rendering, not local UI behavior or data contracts.
  - **Alternatives:** Add tab-switching or table assertions - rejected because those behaviors are no longer part of the slice.

</product-behavior>

<architecture>

### Frontend

- D10: Build the Deal screen in the existing Deals React/MUI microfrontend rather than translating the standalone mockup HTML/CSS directly. **Why:** the screen must fit the portal app stack, theme, routing, and component conventions.
  - **Alternatives:** Reuse the mockup HTML/CSS directly - rejected because it would bypass the actual Deals frontend architecture.
- D11: Keep the routed page wrapper thin and render a `DealMainPanel` from the Deals component area. **Why:** the route file should own TanStack routing concerns, while `DealMainPanel` owns the Deal layout composition that later stories will wire to data and behavior.
- D12: Treat the mockup as the exact visual design contract, not a behavior source. **Why:** the mockup defines the required layout, density, priority, and chrome, but also contains rich sample data, fields, transaction columns, modals, row menus, and actions that exceed this feature's scope.
- D13: Use simple local shell components instead of copying data-oriented components from Clients or Wiretracking. **Why:** this slice needs layout structure, not field display, toggle, table, or permission behavior.
  - **Alternatives:** Copy Clients `FieldDisplay`, `ToggleField`, `SecuredButton`, or Wiretracking layout/table components now - rejected because those components support behavior, chrome, and field detail outside this shell story.
- D14: Use a generic `DealPanel` wrapper with a `title` prop, optional `actions` slot, and body `children` for the Deal header and grid placeholder areas. **Why:** this keeps panel chrome consistent while avoiding a metrics or arbitrary full-header API before the shell needs it.
  - **Alternatives:** Let callers pass full header JSX - rejected because it would make each shell region recreate the same header layout and styling.
- D15: Split shell regions into separate components from the first slice: `DealLookupBar`, `DealHeader`, `DealComments`, and `GridPlaceholder`. **Why:** the story is about creating shell component boundaries, and named components make later data and behavior stories easier to attach without unpacking a large main panel.
  - **Alternatives:** Inline shell regions inside `DealMainPanel` until they grow - rejected because it hides the component boundaries this story is meant to establish.
- D16: Put each named Deals shell component in its own file under `src/Components/Deals/`. **Why:** the component count is small, and one file per component keeps later data-loading, comment, and grid stories from colliding in a catch-all shell file.
  - **Alternatives:** Group shell components in a single `DealShells.tsx` file - rejected because it makes the new component boundaries less visible.
- D17: Use `GridPlaceholder` bodies inside `DealPanel` for transaction areas. **Why:** later grid stories can replace the placeholder body with real grid behavior while preserving the surrounding layout shell.
  - **Alternatives:** Build empty tables now - rejected because transaction columns and table behavior are not required by this shell story.
- D18: Have `DealHeader` compose `DealPanel title="Deal"` with disabled top-level actions, a header-field placeholder, and `DealComments` inside the panel body. **Why:** the header region should use the same panel chrome as the grid placeholders while keeping comments visually inside the header area.
  - **Alternatives:** Let `DealMainPanel` assemble `DealPanel`, header placeholder, and comments directly - rejected because it weakens the header region boundary.
- D19: Do not wire AG Grid in this feature. **Why:** there is no data, row model, column state, permissions, or row behavior yet; the current need is shell layout review.
- D20: Render disabled action button groups inline where they are passed to `DealPanel` rather than introducing an action-cluster component. **Why:** the buttons need consistent presentation, but this shell slice does not need a new abstraction for a small amount of static JSX.
  - **Alternatives:** Add a reusable disabled action cluster component - rejected because it would wrap simple button markup without enough behavior or styling complexity to justify it.

</architecture>

<codebase-findings>

- `code/Camtrade.Portal.UI/deals/src/Pages/Deals/DealsPage.tsx` - the Deals app currently renders a placeholder page that this feature replaces with the Deal screen shell.
- `code/Camtrade.Portal.UI/deals/src/Pages/RouteDefinitions.ts` - the Deals app already maps the index page through the standard TanStack Router virtual-route pattern.
- `code/Camtrade.Portal.UI/deals/package.json` - the Deals app already includes React, MUI, TanStack Router, and AG Grid dependencies, though this feature should not wire AG Grid yet.
- `code/Camtrade.Portal.UI/deals/src/Theme/Theme.ts` - the Deals app has the portal MUI theme and typography used for the new screen.
- `docs/mockups/frmDeal-react-mockup-v2.html` - the provided mockup contains the visual structure, region ordering, shell spacing, and toolbar labels for the layout reference.
- `code/Camtrade.Portal.UI/clients/src/Components/Clients/_main/MainPanel.tsx` - the Clients app uses `MainPanel` for its composed main work surface, which informs the Deals `DealMainPanel` naming and route-boundary split.
- `.codex/knowledge/architecture/deals/deals.md` and `.codex/knowledge/architecture/deals/frontend.md` - the Deals architecture notes capture the current route, component-boundary, disabled-control, and shell-placeholder decisions for CGP-29640.

</codebase-findings>
