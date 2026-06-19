# Deal Stack Skeleton

<problem-intent>

Deals modernization needs backend and service homes to match the already-created Deals React microfrontend before individual legacy Deal behaviors can move out of the VB6 Camtrade application. The modern target architecture expects the existing routed React microfrontend to be backed by a Camtrade Portal BFF area and a Deals domain-service home where later vertical slices can add business behavior.

This feature establishes the missing backend infrastructure locations and verifies the existing frontend placeholder still builds and loads without introducing Deal lookup, grids, business APIs, stored procedures, validation, audit logging, or generated Deal clients. It is foundation work for later Deal conversion stories, not a behavior-preservation slice.

</problem-intent>

<scope>

**In scope**

- Confirm the existing Deals routed React microfrontend skeleton remains correctly configured and buildable.
- Create a Deals BFF area skeleton in Camtrade Portal.
- Create a lightweight Deals domain-service skeleton.
- Provide infrastructure-only health/version checks appropriate to each backend layer.
- Verify the frontend placeholder, Camtrade Portal, and Deals domain-service skeleton build.

**Out of scope**

- Deal lookup, search, header behavior, grids, row actions, and search drawers; later behavior slices own those flows.
- Deal business API contracts, generated Deal clients, and Deals OpenAPI specs; later endpoint slices own those contracts.
- Deal-specific permission enforcement beyond the intentional temporary microfrontend gate; a later permission slice owns the final permission model.
- Validation, audit logging, events, database writes, stored procedures, and legacy behavior reconstruction; later business slices own those responsibilities.
- Legacy VB6 changes; this skeleton must not modify `frmDeal.frm`, `DEAL.bas`, or other legacy code.

</scope>

<product-behavior>

### Flow 1: Load the Deals placeholder

The first modern Deals surface gives authenticated portal users a place to land while later stories add real Deal behavior.

- R1: An authenticated portal user can open the Deals modern app surface and see a placeholder Deals page.
- R2: The placeholder page loads without requiring Deal data, Deal lookup input, search results, grids, row actions, or generated Deal business API clients.
- R3: The placeholder app remains gated by the intentional temporary Deals microfrontend access permission until a later story replaces it with the final Deal permission model.

#### Decisions

- D1: Keep the temporary Deals microfrontend access gate in the skeleton. **Why:** it was intentionally added when the microfrontend was created and protects the new surface while the final permission model is still out of scope.
  - **Alternatives:** Remove all Deal-specific frontend gating - rejected because it would undo the intentionally created temporary app access control.

### Flow 2: Verify deployed skeleton surfaces

The skeleton should be easy to verify after deployment without pretending that Deal business dependencies exist.

- R4: A logged-in portal context can verify that the Deals BFF area is deployed.
- R5: Infrastructure can verify that the Deals domain service is reachable through the standard domain-service version check.

#### Decisions

- D2: Keep deployment checks infrastructure-only. **Why:** this story proves that the new surfaces exist; downstream business health would imply dependencies that are not part of the skeleton.
  - **Alternatives:** Check the Deals domain service, database, generated clients, or legacy code from the BFF health check - rejected because those dependencies are intentionally not introduced by this story.

</product-behavior>

<architecture>

### Frontend

- D3: Treat the existing Deals routed React microfrontend named `deals` as already established. **Why:** the frontend skeleton has already been created with the standard portal shell, routing, startup, theme, API interception, notification, permission, and modal patterns.
- D4: Preserve `deals` as the public app base path and keep local port `3014`. **Why:** the story requested port `3013` unless it was unavailable, and local inspection found `3013` already assigned to Stablecoin.
- D5: Do not add generated Deal business API clients to the existing frontend skeleton. **Why:** the placeholder route must continue to build and load without a Deal business contract.
  - **Alternatives:** Add placeholder generated Deal clients now - rejected because generated clients should be created from the first real Deal API contract.

### BFF

- D6: Create a dedicated Deals BFF area while leaving existing deal-shaped behavior under the Clients BFF area untouched. **Why:** the skeleton establishes the future Deals home without migrating existing behavior before a behavior story owns that move.
  - **Alternatives:** Reuse or relocate the existing Clients Deals controller behavior in this story - rejected because that would turn a skeleton story into a behavior migration.
- D7: Mimic the Stablecoin BFF folder shape: `Controllers`, `Repositories`, `Services`, and `YAMLs`. **Why:** Stablecoin is the selected current convention for this skeleton, and empty future homes should survive in git.
  - **Alternatives:** Add `Entities` and `Utility` folders now - rejected because Stablecoin does not require them for the skeleton and later slices can add them when real files need those homes.
- D8: Include a static Deals BFF health endpoint protected by authenticated portal access, not by a final Deal permission. **Why:** the endpoint proves BFF deployment without introducing a public BFF exception or a premature Deal permission contract.
  - **Alternatives:** Make the BFF health endpoint public - rejected because existing BFF public endpoints are explicit exceptions, while domain services already provide anonymous infrastructure version checks.

### Domain Service

- D9: Use a lightweight single-service Deals domain-service skeleton, closer to Clients or DSTemplate than WireTracking. **Why:** the story needs a buildable home for future Deal behavior, not WireTracking's heavier multi-project structure before there are queues, operations, or business workflows.
  - **Alternatives:** Copy the full WireTracking multi-project solution shape - rejected because it would add complexity not justified by a no-business-endpoints skeleton.
- D10: Configure the Deals domain service with app name `deals` and an empty local self base URL. **Why:** the app name aligns the service with gateway conventions, while the local self base URL remains intentionally unset for local development.
- D11: Expose only the standard anonymous domain-service app-version root endpoint. **Why:** that endpoint is the established gateway health/version convention for domain services.
  - **Alternatives:** Add a separate Deals domain-service health endpoint now - rejected because there are no real Deals dependencies to check yet.
- D12: Do not create a Deals API spec or generated Deals API clients in this skeleton. **Why:** the first real domain endpoint slice should own the OpenAPI contract and generated-client plumbing.

### Validation

- D13: Use build and startup checks as the validation boundary for this skeleton, with frontend work limited to verifying the existing app. **Why:** no Deal business behavior, validation, data access, or API contract is being introduced.

</architecture>

<codebase-findings>

- `code/Camtrade.Portal.UI/deals/` - an existing Deals microfrontend skeleton is present with Rsbuild, TanStack Router, module federation, MenuApp shell integration, theme, startup, API interceptor, notifications, permissions, and modal-dialog scaffolding.
- `code/Camtrade.Portal.UI/deals/env/.env` - the Deals app uses `PUBLIC_APP_BASE_PATH=deals` and currently reserves `APP_BASE_PORT=3014`.
- `code/Camtrade.Portal.UI/Stablecoin/env/.env` - Stablecoin already uses `APP_BASE_PORT=3013`, explaining the Deals port deviation.
- `code/Camtrade.Portal.UI/deals/src/API/SpecReferences.mjs` - the Deals frontend references only the portal auth API spec today, so it does not depend on generated Deal business clients.
- `code/Camtrade.Portal.UI/deals/src/Startup/App.tsx` and `code/Camtrade.Portal.UI/deals/src/Custom/Permissions/permissions.ts` - the Deals frontend includes the intentional temporary microfrontend access gate.
- `code/Camtrade.Portal/BackendForFrontends/Stablecoin/` - the selected BFF skeleton pattern contains `Controllers`, `Repositories`, `Services`, and `YAMLs`.
- `code/Camtrade.Portal/BackendForFrontends/Stablecoin/Controllers/HealthController.cs` - Stablecoin has the closest BFF health example and protects it with portal authorization.
- `code/Camtrade.Portal/Authorization/Middleware/PermissionsMiddleware.cs` - Camtrade Portal API controllers must declare auth or explicit public metadata, so an unauthenticated BFF health endpoint would be a deliberate exception.
- `code/Camtrade.Portal/BackendForFrontends/Clients/` - existing deal-shaped BFF behavior lives under the Clients area and should not be treated as migrated by this skeleton.
- `code/DomainServices/*/Controllers/AppVersionController.cs` - domain services commonly expose anonymous app-version root endpoints used for gateway health/version checks.
- `code/DomainServices/Clients/` and `code/DomainServices/DSTemplate/` - these services provide the lighter skeleton convention selected for the initial Deals domain service.
- `code/DomainServices.ApiSpecs/` - API specs exist for established domain services, but no Deals API spec is needed until a real Deal domain endpoint exists.

</codebase-findings>
