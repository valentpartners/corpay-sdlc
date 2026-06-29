# Deals Frontend Architecture

Frontend Deals work lives in `code/Camtrade.Portal.UI/deals/`.

## Known Anchors

- The initial routed app skeleton uses `PUBLIC_APP_BASE_PATH=deals`.
- Local port `3013` is unavailable because Stablecoin uses it; the Deals skeleton currently reserves `APP_BASE_PORT=3014`.
- `UR_Temp_Deals_Page` is an intentional temporary microfrontend access gate, not the final Deals permission contract.
- API generation should use the routed-app pattern: run `pnpm run genallapis` from `code/Camtrade.Portal.UI/deals/`.

## Deal Screen Shell

- CGP-29640 establishes the first Deal screen layout at the existing `/deals` index route.
- The Deal screen layout should use `docs/mockups/frmDeal-react-mockup-v2.html` as the visual design contract while staying in the Deals React/MUI stack.
- Keep `src/Pages/Deals/DealsPage.tsx` as a thin route wrapper that renders `DealMainPanel` from `src/Components/Deals/`.
- Put reusable Deal screen pieces under `src/Components/Deals/`.
- Render shell-only regions for the first layout slice: Deal lookup/navigation, Deal header, comments, Buy/Sell, Settlement, Payment, and Income/Expense.
- Do not add fake header field data, a typed Deal fixture, transaction columns, or Income/Expense tab behavior in the shell slice.
- Match the mockup's dense workbench design: use available vertical space, keep the Deal header compact enough for the one-row direction, make Settlement and Payment the most important grid regions, and keep enough contrast between grid shells for review.

## Lookup And Navigation Shell

- For CGP-29640, render Deal # and Order # lookup fields that write trimmed values to temporary `dealId` and `orderNumber` search parameters.
- Those search parameters are only a developer/testing affordance for lookup bar and downstream placeholder wiring. They are not the final Deal launch or data-loading contract.
- Keep previous/next navigation controls disabled in the shell slice.
- Omit an explicit Load control for now.
- Do not call Deals APIs or domain services from the lookup shell slice. Later data-loading work owns the durable lookup contract, validation rules, launch behavior, and whether Deal lookup needs an explicit Load control.

## Component Boundaries

- Keep component patterns local and shell-focused for now: `DealMainPanel`, `DealPanelHeader`, `DealLookupBar`, `DealHeader`, `DealComments`, `TempGridComponent`, `SettlementsGrid`, `PaymentsGrid`, `BuySellGrid`, and `IncomeExpenseGrid`.
- Create shell region components separately from the first slice rather than inlining them in `DealMainPanel`.
- Keep one named component per file under `src/Components/Deals/`.
- Do not copy Clients `FieldDisplay`, `ToggleField`, `SecuredButton`, or Wiretracking layout/table components; Deals should own components that match the mockup.
- For CGP-29640, Deal sections should use a durable `DealPanelHeader` for title, optional actions, and fullscreen controls.
- Transaction grid wrappers should render `DealPanelHeader` and then the temporary self-contained `TempGridComponent` body as a sibling, not tables, row action columns, row menus, Deal API calls, or AG Grid wiring.
- Render disabled action button groups inline where they are passed to `DealPanelHeader`; do not introduce an action-cluster component until later behavior or styling complexity justifies it.

## Region Layout

- Compose `DealComments` inside `DealHeader` to match the mockup's header-area placement while keeping comments as a separate shell component.
- `DealHeader` should own its section shell and render `DealPanelHeader title="Deal"` with disabled top-level actions, a header-field placeholder, and `DealComments` below it.
- `DealComments` may include temporary local tab selection and collapse/expand behavior so developers can exercise the header shell. Later comments stories own durable comment data, tabs, validation, and persistence.
- Arrange transaction grid shells to match the mockup spans: Settlement and Payment span the full content width, while Buy/Sell and Income/Expense share a two-column row on desktop and stack on constrained widths.

## Later Frontend Notes

- Do not add generated frontend clients for CGP-29639/CGP-29642. Later UI data-loading work owns frontend generation and query wiring.
- Later grid stories should add alternating row colors once real transaction rows exist.
- Later fullscreen grid stories must preserve row-level actions; fullscreen must not hide or drop row action affordances.
- Later add/edit stories should open complete-input modals for header or transaction edits. Those modals may take the whole screen when the workflow needs the space.
- Later header persistence should follow the legacy Deals pattern: one synchronous save action validates and updates the Deal top to bottom, including the legacy validation set currently understood as 32 validations.
- Later payment-restriction work should keep the restriction banner only as wide as it needs to be; the Edit button belongs to the Deal header, not to the banner.
