# Deals BFF Architecture

Deals BFF work lives in `code/Camtrade.Portal/BackendForFrontends/Deals/`.

## Known Anchors

- The dedicated Deals BFF skeleton is under `code/Camtrade.Portal/BackendForFrontends/Deals/`.
- Existing deal-shaped BFF behavior also exists under `code/Camtrade.Portal/BackendForFrontends/Clients/`; inspect it as prior art, but do not assume new Deals behavior belongs there.
- Mimic the Stablecoin BFF folder shape for now: `Controllers/`, `Repositories/`, `Services/`, and `YAMLs/`.
- Do not add `Entities/` or `Utility/` folders in the Deals BFF skeleton unless a later slice introduces files that need them.

## Deal Header Endpoint

- CGP-29639/CGP-29642 replaces placeholder Deals health API generation with the first real backend Deals BFF operation: a current Deal Header read model.
- Remove the Deals BFF health controller and `healthController.yaml` when adding the first real Deal Header endpoint; health was temporary scaffold behavior.
- Expose the portal-facing Deal Header endpoint through a Deals controller YAML with stable operation id `getDealHeader`.
- Require `UR_Deal_Read` for the Deal Header endpoint. Do not infer access from broader Deal write/action permissions unless a later story changes the permission model.
- Return `400 Bad Request` at the BFF contract edge for a blank trimmed `dealNumber` or a trimmed `dealNumber` longer than 12 characters. Do not call the domain service for malformed requests.
- Return `403 Forbidden` only when the caller lacks `UR_Deal_Read`.
- Return `404 Not Found` when `camtrade_GetDealInfo` returns no visible row, including rows hidden by the procedure's user-key sales-number filtering. Do not leak whether the row was missing or restricted.
- Return the successful `DealHeader` object directly from `getDealHeader`; do not wrap it in a `{ data: ... }` envelope.
- Keep the BFF thin for Deal Header: portal auth, logging, error shaping, and generated contract exposure belong here; stored-procedure execution and raw column mapping belong in the Deals domain service.

## Generated Client And User Key

- The BFF calls the Deals domain service through the generated `DSApis.Deals` client registered in `code/Camtrade.Portal/Program.cs`.
- Do not expose `userKey` in frontend-facing request input.
- Do not add `userKey` to the BFF-to-domain-service OpenAPI operation as an explicit generated method parameter for this feature. Use the existing server-owned user-key header propagation path.
- The successful domain-service response should already match the BFF payload shape closely enough for thin pass-through behavior.

## Later BFF Notes

- Later UI data-loading work owns frontend generation, query wiring, and route/UI behavior around invoking `getDealHeader`.
- Order lookup and previous/next navigation are out of scope for the first Deal Header backend endpoint.
