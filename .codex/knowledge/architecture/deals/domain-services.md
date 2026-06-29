# Deals Domain Services Architecture

Deals domain-service work lives in `code/DomainServices/Deals/`.

## Known Anchors

- The Deals domain-service skeleton is under `code/DomainServices/Deals/`.
- Existing candidates such as `code/DomainServices/Orders/` may still own current deal behavior until migration slices decide ownership.
- Use a lightweight single-service skeleton for now, closer to `DomainServices/Clients` or `DomainServices/DSTemplate` than the heavier WireTracking multi-project solution.
- The skeleton should expose only the standard anonymous app-version root endpoint used by domain services for gateway health/version checks.
- Do not add a separate `/deals/health` domain-service endpoint until a later slice has real Deals dependencies to check.

## Deal Header Domain Endpoint

- CGP-29639/CGP-29642 is the first real Deals domain endpoint slice.
- Add and register `DomainServices.ApiSpecs/dealsApi.yaml` for the clean Deal Header contract; do not create empty reservation specs.
- Keep the Deals domain-service OpenAPI clean and intent-based for the BFF: accept a current Deal-number input as a trimmed `dealNumber` string.
- Do not expose legacy `searchtype`, `searchdir`, or `ischanged` procedure flags in generated clients.
- Do not expose `userKey` in the BFF-to-domain-service OpenAPI contract as a generated method parameter for this feature. The runtime should read the server-owned user-key header/context supplied by the existing middleware path.

## Legacy Procedure Boundary

- Execute `camtrade_GetDealInfo` in the Deals domain service and map its raw columns to clean flat Deal Header names at the repository/service boundary.
- Translate current Deal-number lookup into the stored procedure's Deal search parameters inside the domain service.
- Pass the server-owned user key to `camtrade_GetDealInfo` so the procedure's sales-number filtering remains in force.
- Exact-match the returned Deal number. If the procedure returns a nearest different Deal, treat it as not found.
- Normalize null, empty, and whitespace-only strings to null in the Deal Header contract.
- Keep dates, numbers, and booleans typed and nullable when absent.

## Later Domain-Service Notes

- Later Deal read models should decide ownership explicitly before adding behavior to BFF or Clients-shaped services.
- Mutations, update validations, reversal, clone, finish, and transaction-grid data need separate domain-service stories.
