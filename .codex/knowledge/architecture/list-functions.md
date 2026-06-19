# List Functions Workstream Architecture

List Functions modernizes shared list/configuration-style functions from legacy Camtrade into the modern portal.

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known list-function-related forms include `frmListFuncSecurity.frm`.
  - Search legacy forms for list maintenance, list security, and lookup/configuration behavior before implementation.
- Microfrontend: `code/Camtrade.Portal.UI/ListFunctions/`
- BFF: `code/Camtrade.Portal/BackendForFrontends/ListFunctions/`
- Domain services: no dedicated `ListFunctions` domain service has been confirmed yet; inspect `code/DomainServices/ConfigManager/` and related shared/config services during discovery.

## Discovery Checklist

- Identify whether the list is configuration data, security/permission data, or workflow reference data.
- Confirm owning service before adding persistence or rules.
- Watch for shared list behavior used across Deals, Accounts, Clients, and Wiretracking.
- Treat BFF manifest handling as a List Functions-specific pattern: manifests are loaded once, user-specific filtering should work on copies, and permission/default/validation behavior should remain centralized in the manifest service.

## Notes To Grow

- Legacy forms:
- Modern UI entry points:
- BFF endpoints:
- Domain service controllers/services/repositories:
- Test projects:
