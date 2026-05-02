# Changelog

## Unreleased

### Added

- Initial repository split for Kubernetes platform tools.
- Added modules for platform, observability, Argo CD, Keycloak runtime, and Keycloak configuration.
- Documented the boundary between cloud infrastructure modules and Kubernetes application/tool modules.
- Added Kiali OIDC proxy headers and included the OIDC issuer host in observability egress ServiceEntries.
- Scoped public ServiceEntries to the Istio root namespace and allowed platform-owned waypoint labels on tool namespaces.

### Decisions

- Keep OCI/IaaS resources in `terraform-oci-modules-af`.
- Keep Helm, Kubernetes manifests, and application providers in this repository.
- Run Keycloak runtime and Keycloak provider configuration in separate phases because the provider authenticates during planning.
- Do not attach Argo CD to MySQL; Argo CD uses Kubernetes as its source of persisted cluster state and Redis as cache.
