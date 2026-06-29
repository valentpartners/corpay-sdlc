# Clients Workstream Architecture

Clients modernizes client maintenance and client search workflows from legacy Camtrade into the modern portal.

## Layer Notes

- Frontend: [frontend.md](frontend.md)
- BFF: [bff.md](bff.md)
- Domain services: [domain-services.md](domain-services.md)

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known client-related forms include `CLI.FRM`, `CliList.frm`, `frmClientSearch.frm`, `frmClientTags.frm`, `frmClientExposure.frm`, and `frmClientWireTransfer.frm`.
- Microfrontends:
  - `code/Camtrade.Portal.UI/clients/`
  - `code/Camtrade.Portal.UI/ClientMaintenance/`
- BFF:
  - `code/Camtrade.Portal/BackendForFrontends/Clients/`
  - `code/Camtrade.Portal/BackendForFrontends/ClientMaintenance/`
- Domain services:
  - `code/DomainServices/Clients/`
  - `code/DomainServices/ClientMaintenance/`

## Discovery Checklist

- Distinguish client lookup/search behavior from client maintenance/editing behavior.
- Use legacy forms to identify required fields, validation, permissions, and workflow sequencing.
- Confirm whether a change belongs in `clients`, `ClientMaintenance`, or both.

## Notes To Grow

- Legacy forms:
- Modern UI entry points:
- BFF endpoints:
- Domain service controllers/services/repositories:
- Test projects:
