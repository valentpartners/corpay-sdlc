# Wiretracking Workstream Architecture

Wiretracking modernizes wire tracking and operations workflows from legacy Camtrade into the modern portal.

## Layer Notes

- Frontend: [frontend.md](frontend.md)
- BFF: [bff.md](bff.md)
- Domain services: [domain-services.md](domain-services.md)

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known wire/payment-related forms include `frmClientWireTransfer.frm`, `frmOriginalWire.frm`, `frmIncomingList.frm`, `frmincoming.frm`, and related incoming/payment forms.
- Microfrontend: `code/Camtrade.Portal.UI/wiretracking/`
- BFF: `code/Camtrade.Portal/BackendForFrontends/Wiretracking/`
- Domain services: `code/DomainServices/WireTracking/`
  - Notable subprojects include API, Application, Operations, Queue, Repository, and test projects under `code/DomainServices/WireTracking/`.

## Discovery Checklist

- Identify whether the story belongs to queue behavior, operations behavior, repository/persistence, or UI workflow.
- Trace wire status transitions carefully; do not infer state-machine behavior without checking legacy forms and domain-service tests.
- Use existing WireTracking test projects as the first source for modern expected behavior.

## Notes To Grow

- Legacy forms:
- Modern UI entry points:
- BFF endpoints:
- Domain service controllers/services/repositories:
- Test projects:
