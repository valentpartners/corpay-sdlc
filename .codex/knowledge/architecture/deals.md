# Deals Workstream Architecture

Deals modernizes legacy deal workflows from the VB6 Camtrade application into the modern portal.

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known deal-related forms include `DDEAL.FRM` and `frmDeal.frm`.
  - Search `code/Camtrade/**/*.FRM` for deal-specific forms and event handlers before implementation.
- Microfrontend: `code/Camtrade.Portal.UI/deals/`
  - The initial routed app skeleton uses `PUBLIC_APP_BASE_PATH=deals`.
  - Local port `3013` is unavailable because Stablecoin uses it; the Deals skeleton currently reserves `APP_BASE_PORT=3014`.
  - `UR_Temp_Deals_Page` is an intentional temporary microfrontend access gate, not the final Deals permission contract.
  - API generation should use the routed-app pattern: run `pnpm run genallapis` from `code/Camtrade.Portal.UI/deals/`.
  - The current API generation slice registers `camtradePortalAuth`, `camtradeLaunch`, and Deals `health`; do not register a `deals` frontend client until the first real Deals BFF operation exists.
- BFF: planned dedicated skeleton at `code/Camtrade.Portal/BackendForFrontends/Deals/`; existing deal-shaped BFF behavior also exists under `BackendForFrontends/Clients/`.
  - The skeleton should create a Deals controller with a Stablecoin-style health endpoint at `GET /api/deals/health`.
  - The BFF health endpoint should require an authenticated portal user, not a Deal-specific permission, and should perform no downstream domain-service, database, generated-client, or legacy checks.
  - Mimic the Stablecoin BFF folder shape for now: `Controllers/`, `Repositories/`, `Services/`, and `YAMLs/`.
  - Keep `healthController.yaml` scoped to the health endpoint; future business operations should go in their own Deals controller YAML instead of reusing the health contract.
  - Do not add `Entities/` or `Utility/` folders in the skeleton unless a later slice introduces files that need them.
- Domain services: planned skeleton at `code/DomainServices/Deals/`; existing candidates such as `code/DomainServices/Orders/` may still own current deal behavior until migration slices decide ownership.
  - Use a lightweight single-service skeleton for now, closer to `DomainServices/Clients` or `DomainServices/DSTemplate` than the heavier WireTracking multi-project solution.
  - The skeleton should expose only the standard anonymous app-version root endpoint used by domain services for gateway health/version checks.
  - Do not add a separate `/deals/health` domain-service endpoint until a later slice has real Deals dependencies to check.
  - Do not add or register `DomainServices.ApiSpecs/dealsApi.yaml` until the first real Deals domain endpoint exists; an empty `paths: {}` contract should not be generated or registered just to reserve the client.
  - Do not add Deals domain-service DI registration, repository usage, generated-client usage, or BFF calls until a real Deals domain endpoint exists.

## Discovery Checklist

- Identify the legacy `.FRM` screen and any related `.BAS` / `.CLS` modules.
- Map user-visible behavior before mapping fields or database calls.
- Find the modern route, module federation entry, API client, and BFF endpoint for the Deals microfrontend.
- Confirm which domain service owns each rule before adding logic to the BFF.

## Notes To Grow

- Legacy forms:
- Modern UI entry points:
- BFF endpoints:
- Domain service controllers/services/repositories:
- Test projects:
