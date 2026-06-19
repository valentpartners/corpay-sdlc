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
- BFF: planned dedicated skeleton at `code/Camtrade.Portal/BackendForFrontends/Deals/`; existing deal-shaped BFF behavior also exists under `BackendForFrontends/Clients/`.
  - The skeleton should create a Deals controller with a Stablecoin-style health endpoint at `GET /api/deals/health`.
  - The BFF health endpoint should require an authenticated portal user, not a Deal-specific permission, and should perform no downstream domain-service, database, generated-client, or legacy checks.
  - Mimic the Stablecoin BFF folder shape for now: `Controllers/`, `Repositories/`, `Services/`, and `YAMLs/`.
  - Do not add `Entities/` or `Utility/` folders in the skeleton unless a later slice introduces files that need them.
- Domain services: planned skeleton at `code/DomainServices/Deals/`; existing candidates such as `code/DomainServices/Orders/` may still own current deal behavior until migration slices decide ownership.
  - Use a lightweight single-service skeleton for now, closer to `DomainServices/Clients` or `DomainServices/DSTemplate` than the heavier WireTracking multi-project solution.
  - The skeleton should expose only the standard anonymous app-version root endpoint used by domain services for gateway health/version checks.
  - Do not add a separate `/deals/health` domain-service endpoint until a later slice has real Deals dependencies to check.
  - Do not create `DomainServices.ApiSpecs/dealsApi.yaml` or generated Deals API clients in the skeleton story; the first real domain endpoint slice owns that contract.

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
