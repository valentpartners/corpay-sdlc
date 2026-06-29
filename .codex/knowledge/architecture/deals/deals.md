# Deals Workstream Architecture

Deals modernizes legacy deal workflows from the VB6 Camtrade application into the modern portal.

## How To Use These Notes

Read this file first for Deals workstream context, then read only the layer notes relevant to the story:

- Frontend: [frontend.md](frontend.md)
- BFF: [bff.md](bff.md)
- Domain services: [domain-services.md](domain-services.md)

Keep durable cross-layer decisions here. Put concrete component, endpoint, generated-client, controller, repository, and test ownership details in the matching layer file.

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known deal-related forms include `DDEAL.FRM` and `frmDeal.frm`.
  - Search `code/Camtrade/**/*.FRM` and related `.BAS` / `.CLS` modules for deal-specific forms and event handlers before implementation.
- Microfrontend: `code/Camtrade.Portal.UI/deals/`
- BFF: `code/Camtrade.Portal/BackendForFrontends/Deals/`
  - Existing deal-shaped BFF behavior may also exist under `code/Camtrade.Portal/BackendForFrontends/Clients/`.
- Domain service: `code/DomainServices/Deals/`
  - Existing candidates such as `code/DomainServices/Orders/` may still own current deal behavior until migration slices decide ownership.

## Cross-Layer Decisions

- Use the legacy VB6 implementation to recover behavior and workflow sequencing, not as a code-style template.
- Keep Deals UI shell/layout stories separate from backend data-loading stories. A backend-only Deal Header story must not add frontend generated clients, query hooks, route wiring, or loaded header rendering.
- Current Deal Header lookup is current Deal-number lookup only. Order lookup and previous/next navigation need later UI/data-loading decisions.
- The Deal Header payload is a broad reusable backend read model for future Deal screen components. Return the full legacy header row so later components can consume one fetch instead of creating duplicate header requests.
- Preserve legacy row visibility by propagating the server-owned user key to the Deals domain service for `camtrade_GetDealInfo` sales-number filtering. Do not accept user key from frontend request input.
- The successful Deal Header BFF response is the `DealHeader` object directly, not a `{ data: ... }` envelope.

## Discovery Checklist

- Identify the legacy `.FRM` screen and any related `.BAS` / `.CLS` modules.
- Map user-visible behavior before mapping fields or database calls.
- Find the modern route, module federation entry, API client, and BFF endpoint for the Deals microfrontend.
- Confirm which domain service owns each rule before adding logic to the BFF.
- Read the relevant layer note before editing files in that layer.

## Notes To Grow

- Legacy forms:
- Modern UI entry points: see [frontend.md](frontend.md).
- BFF endpoints: see [bff.md](bff.md).
- Domain service controllers/services/repositories: see [domain-services.md](domain-services.md).
- Test projects:
