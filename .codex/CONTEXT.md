# Domain Glossary

Ubiquitous language for Deals development at Corpay.

## Terms

- **Deals** - The Corpay product area being rebuilt from legacy behavior into a new microfrontend experience.
- **Legacy Deals application** - The existing application used as the behavioral reference for the rebuild.
- **Deals microfrontend** - The new React/TypeScript frontend implementation for Deals features in the Corpay monorepo.
- **BFF layer** - The backend-for-frontend layer that shapes API interactions for the Deals microfrontend.
- **Domain services** - .NET/C# services that own Deals business capabilities and backend behavior.
- **Corpay monorepo** - The repository where Deals feature code is implemented, built, tested, and committed.

## Preferred Language

- Use "Deals" for the product area.
- Use "legacy Deals application" for the existing behavior source.
- Use "Deals microfrontend" for the new frontend surface.
- Avoid treating this support repo as the application repo; implementation commands run from the Corpay monorepo.
