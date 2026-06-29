# Deal Header API

<problem-intent>

Deals modernization needs its first real backend read surface so future Deal screen work can load legacy Deal header data through the modern BFF and domain-service architecture instead of relying on placeholder backend health scaffolding. The current Deals stack has skeleton backend locations and a visual shell, but no generated backend business API contract for loading a Deal.

This feature replaces the temporary Deals health API surface with a backend-only Deal Header read model. It stops at the BFF endpoint, the Deals domain-service endpoint, backend OpenAPI contracts, and the generated BFF-to-domain-service client. It does not create frontend generated clients, wire the Deal screen, render loaded header values, support Order lookup, or support previous/next navigation.

</problem-intent>

<scope>

**In scope**

- Replace the temporary Deals BFF health API surface with a real Deals header read endpoint.
- Add a Deals domain-service read endpoint backed by the legacy Deal header stored procedure.
- Register backend OpenAPI contracts so the BFF can call the Deals domain service through the generated domain-service client.
- Load one current Deal header row by Deal number.
- Return a clean flat Deal header contract containing the full legacy header row.
- Normalize null, empty, and whitespace-only legacy values for modern consumers.
- Enforce the story's Deal read permission and preserve legacy user sales-number row filtering.
- Validate malformed Deal-number inputs at the BFF contract edge before calling the domain service.

**Out of scope**

- Frontend generated Deals API clients, frontend query hooks, Deal screen data wiring, or rendering loaded header values.
- Order-number lookup; later UI/data-loading work owns whether and how Order lookup is exposed.
- Previous and next Deal navigation; later UI/data-loading work owns navigation semantics.
- Deal save, update, delete, reversal, clone, finish, or other mutations; those require separate write stories.
- Transaction grids, Buy/Sell, Settlement, Payment, Income/Expense data, and row actions; this feature only owns the header procedure result.
- Comment editing, comment save behavior, comment permissions, and comment UI interactions; comments are returned only because the header procedure already returns them.
- Financial summary behavior and other non-header Deal calculations; those need separate read models.
- Legacy VB6 or stored procedure changes; this feature adapts existing behavior into modern backend services.
- Broad Deal permission modeling beyond the story's read permission; later permission work owns broader Deal action access.

</scope>

<product-behavior>

### Flow 1: Load a current Deal header

An authorized caller can request the current Deal header from the modern backend Deals data surface using a Deal number.

- R1: A caller with Deal read access can request the Deal header for a typed Deal number.
- R2: The loaded header includes the full legacy header row, including identifiers, client details, date fields, status fields, option fields, comments, related deals, Salesforce case fields, MT300 fields, flags, counts, and fields not rendered by the current Deal screen.
- R3: Header values that are absent or blank in legacy data are exposed as absent values to modern consumers.
- R4: A successful lookup returns the Deal Header payload directly, not wrapped in a data envelope.
- R5: A caller who lacks Deal read access receives a forbidden response.
- R6: A lookup that returns no row because the Deal does not exist or is hidden by legacy user sales-number filtering receives a not-found response; the API does not distinguish hidden Deals from missing Deals.
- R7: A blank Deal number or a trimmed Deal number longer than 12 characters returns a bad-request response without calling the domain service.
- R8: A current lookup that does not resolve to the requested Deal number is treated as not found.
- R9: The backend read operation accepts the Deal number as a trimmed string, preserves leading zeros, and avoids numeric parsing.
- R10: The BFF-to-domain-service call uses the server-owned user key so the legacy sales-number filter remains in force.

#### Decisions

- D1: Return the full stored-procedure result as one broad Deal header read result, not only fields rendered by the current screen. **Why:** the procedure already returns the complete header row, and later Deal components can reuse the broad fetch instead of each creating a competing header request.
  - **Alternatives:** Limit the response to only fields visible in the first header mockup - rejected because it would discard data the legacy procedure already provides and force later components to invent duplicate fetches.
- D2: Treat returned comment fields as read-model data, not comment behavior. **Why:** the procedure returns comments as part of the header row, but comment editing and persistence remain separate responsibilities.
  - **Alternatives:** Exclude comment fields until a comment story exists - rejected because the broad read result intentionally returns everything from the procedure.
- D3: Return not found for missing rows and rows hidden by sales-number filtering. **Why:** both cases produce no visible Deal for the caller, and distinguishing them would leak that a restricted Deal exists.
  - **Alternatives:** Return forbidden when the procedure hides a row - rejected because that would reveal authorization-sensitive existence information.
- D4: Return the successful Deal Header payload directly, without a data envelope. **Why:** this is a single-object read like Clients header loading, and metadata, warnings, and paging are not part of this endpoint's contract.
  - **Alternatives:** Wrap the header in a data envelope - rejected because it adds generated-client noise without adding useful response semantics.
- D5: Keep this story to current Deal-number lookup only. **Why:** this is the backend prerequisite for the first Deal header read, while Order lookup and previous/next navigation need later UI/data-loading decisions.
  - **Alternatives:** Include Order lookup and previous/next navigation now - rejected because those behaviors expand the story beyond the intended backend-only current Deal read.
- D6: Add exact-match protection for current lookups. **Why:** the legacy procedure can return the nearest row because its comparison is inclusive, but a typed current lookup should not silently load a different Deal.
  - **Alternatives:** Preserve nearest-row behavior for current lookup - rejected because it is surprising in a modern API and makes typed lookup failures ambiguous.
- D7: Keep the Deal number as a trimmed string with the same maximum length as the legacy procedure, preserving leading zeros and avoiding numeric parsing. **Why:** Deal numbers are legacy string identifiers, and the procedure compares them as strings.
  - **Alternatives:** Treat Deal numbers as numeric values - rejected because that could drop meaningful leading zeros and misrepresent the legacy identifier shape.

</product-behavior>

<architecture>

### BFF

- D8: Keep the BFF as a thin authenticated pass-through for the Deal header read. **Why:** the BFF owns portal auth, error shaping, logging, and generated contract exposure, while the domain service owns the legacy procedure boundary.
  - **Alternatives:** Map raw stored-procedure columns in the BFF like the Clients header mapper - rejected because the Clients BFF header composes cleaner service data, while this feature's raw legacy boundary lives in the Deals domain service.
- D9: Expose Deal Header lookup as one generated read operation with a Deal-number input. **Why:** the generated backend contract should present one stable current Deal read operation without leaking legacy stored-procedure mechanics.
  - **Alternatives:** Expose legacy search type, direction, or changed flags in the BFF contract - rejected because those parameters are procedure mechanics, not product vocabulary for this story.
- D10: Validate blank and too-long Deal numbers at the BFF contract edge before calling the domain service. **Why:** malformed requests are client input errors, while valid lookups that return no visible row are not-found outcomes.
  - **Alternatives:** Let the domain service or stored procedure reject malformed input - rejected because the BFF owns the portal-facing contract and generated-client error shape.
- D11: Enforce the story's Deal read permission at the BFF. **Why:** the story explicitly grants access to callers with Deal read permission, and broader Deal action permissions should not be inferred.
  - **Alternatives:** Reuse the broader Deal launch permission family - rejected because that would expand access beyond the story.
- D12: Return not found when the domain service returns no visible header row, whether the row is missing or filtered by the user key. **Why:** the BFF should expose the caller's visible result without leaking restricted Deal existence.
- D13: Return the successful Deal Header payload directly, without a data envelope. **Why:** this is a single-object read like Clients header loading, and metadata, warnings, and paging are not part of this endpoint's contract.
  - **Alternatives:** Wrap the header in a data envelope - rejected because it adds generated-client noise without adding useful response semantics.
- D14: Remove the Deals BFF health controller and health OpenAPI contract. **Why:** the real Deal header endpoint replaces the temporary BFF scaffold.
- D15: Maintain separate BFF and domain-service API specs. **Why:** the BFF exposes the portal-facing contract, while the BFF uses the generated domain-service client contract to call the Deals service.
  - **Alternatives:** Use only one spec or hand-roll the service call - rejected because it would break the established generated-client workflow.

### Domain Service

- D16: Execute and adapt the existing legacy Deal header stored procedure in the Deals domain service. **Why:** this keeps SQL execution, procedure-parameter translation, and raw column mapping at the service boundary that owns legacy data access.
- D17: Expose the BFF-to-domain-service Deal Header API with a clean Deal-number input. **Why:** the generated domain-service client should not leak stored-procedure flags into the BFF.
  - **Alternatives:** Expose legacy stored procedure flags in the domain-service OpenAPI - rejected because those are procedure mechanics that belong inside the Deals domain-service implementation.
- D18: Map stored-procedure columns to clean modern field names in the domain service. **Why:** consumers should use stable domain names, while tests can preserve traceability to legacy aliases.
  - **Alternatives:** Expose legacy SQL aliases directly - rejected because it leaks procedure naming into the modern contract.
- D19: Keep the header contract flat. **Why:** the source procedure returns a single broad row rather than nested aggregates.
  - **Alternatives:** Nest fields into header, comments, flags, and related groups - rejected because it adds structure not present at the source and makes broad reuse less direct.
- D20: Normalize null, empty, and whitespace-only strings to absent values in the read contract. **Why:** consumers should render blanks consistently while the API avoids preserving legacy filler whitespace.
  - **Alternatives:** Return empty strings for blank legacy values - rejected because absent values are easier for modern consumers to distinguish from real text.
- D21: Translate the current Deal-number lookup into the legacy procedure's Deal search parameters inside the service. **Why:** the modern contract should expose a simple backend current Deal read while the service shields callers from procedure flags.
- D22: Apply exact-match protection after the stored procedure returns. **Why:** if the procedure returns a different nearest Deal, the modern current lookup should behave as not found.
- D23: Propagate the user key through the existing server-owned BFF-to-domain-service user-key mechanism and pass it to the procedure for sales-number filtering. **Why:** the procedure already uses the user key to restrict rows by legacy sales-number access, and identity context must not be exposed as a generated API parameter.
  - **Alternatives:** Accept user key from the frontend or caller - rejected because identity and row-visibility context must remain server-owned.

### Validation

- D24: Validate the feature at the contract and mapping boundaries. **Why:** the risk is primarily parameter translation, procedure-column mapping, authorization, not-found semantics, and generated backend-client registration.
  - **Alternatives:** Rely only on manual endpoint testing - rejected because this feature introduces reusable generated contracts and legacy mapping logic.

</architecture>

<codebase-findings>

- `code/db-camtrade/Procedures/camtrade_GetDealInfo.sql` - the legacy procedure accepts search type, search value, direction, changed flag, and user key parameters; returns one broad header row; filters rows through `usersalesnum` for the supplied user key.
- `code/Camtrade/DEAL.bas` - `GetDealInfo` calls `camtrade_GetDealInfo`, while `UpdateDeal` is separate, confirming the header procedure is read behavior rather than save/update behavior.
- `code/Camtrade/frmDeal.frm` - `PopulateDealInfo` consumes the procedure result into header fields, comment fields, flags, Salesforce case controls, MT300 controls, related deals, and option fields; adjacent navigation and Order lookup behavior remain out of scope for this backend-only story.
- `code/Camtrade.Portal/BackendForFrontends/Deals/Controllers/HealthController.cs` - the current Deals BFF surface is placeholder health scaffolding that this feature removes.
- `code/Camtrade.Portal/BackendForFrontends/Deals/YAMLs/healthController.yaml` - the current Deals BFF OpenAPI surface documents only the placeholder health endpoint.
- `code/DomainServices/Deals/` - the Deals domain-service skeleton exists, but it does not yet expose a real Deals business read endpoint.
- `code/DomainServices.ApiSpecs/` - established domain services have API specs, but there is no Deals API spec yet.
- `code/Camtrade.Portal/CamtradePortal.csproj` - Camtrade Portal registers generated domain-service API clients through OpenAPI references, and Deals is not yet registered there.
- `code/Camtrade.Portal/BackendForFrontends/Clients/Services/ClientsService.cs` - the Clients BFF composes its header response from multiple service calls before returning a broad header object.
- `code/Camtrade.Portal/BackendForFrontends/Clients/Entities/Responses/ClientHeader.cs` - Clients maps backend data into clean BFF field names rather than exposing backend names directly.
- `code/Camtrade.Portal/Authorization/Permissions.cs` - `UR_Deal_Read` exists as the story's read permission for the new header endpoint.
- `code/Camtrade.Portal/HttpPipeline/UserKeyHeaderDelegatingHandler.cs` - Camtrade Portal already has a server-side user-key propagation mechanism for outgoing domain-service calls.

</codebase-findings>
