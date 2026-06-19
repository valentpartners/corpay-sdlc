# Accounts Workstream Architecture

Accounts modernizes account-related Camtrade workflows into the modern portal.

## Known Anchors

- Legacy reference: `code/Camtrade/`
  - Known account-related forms include `ACT.FRM`, `ACU.FRM`, and `frmAccountCategory.frm`.
  - Search `code/Camtrade/**/*.FRM` for account, deposit, bank, payment, and multi-currency account flows as needed.
- Microfrontend: `code/Camtrade.Portal.UI/accounts/`
- BFF: no dedicated `Accounts` BFF folder has been confirmed yet; inspect `code/Camtrade.Portal/BackendForFrontends/` and shared services during feature discovery.
- Domain services: likely candidates include `code/DomainServices/MultiCurrencyAccounts/`, `code/DomainServices/Payments/`, and `code/DomainServices/Beneficiaries/`.

## Discovery Checklist

- Identify the legacy form and whether it represents account maintenance, bank-account setup, payment rails, or reporting behavior.
- Prefer modern domain-service ownership for account rules; keep BFF logic focused on API composition and shaping.
- Trace generated API clients and DTOs before adding new client-side contracts.

## Notes To Grow

- Legacy forms:
- Modern UI entry points:
- BFF endpoints:
- Domain service controllers/services/repositories:
- Test projects:
