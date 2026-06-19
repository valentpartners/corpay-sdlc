# Deals Workstream Architecture

Deals modernizes legacy deal workflows from the VB6 Camtrade application into the modern portal.

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known deal-related forms include `DDEAL.FRM` and `frmDeal.frm`.
  - Search `code/Camtrade/**/*.FRM` for deal-specific forms and event handlers before implementation.
- Microfrontend: `code/Camtrade.Portal.UI/deals/`
- BFF: no dedicated `Deals` BFF folder has been confirmed yet; inspect `code/Camtrade.Portal/BackendForFrontends/` and shared services during feature discovery.
- Domain services: likely candidates include `code/DomainServices/Orders/` and related order/deal services.

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
