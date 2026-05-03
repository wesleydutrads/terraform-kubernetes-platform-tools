# Changelog

## Unreleased

### Added

- Initial repository split for Kubernetes platform tools.
- Added modules for platform, observability, Argo CD, Keycloak runtime, and Keycloak configuration.
- Documented the boundary between cloud infrastructure modules and Kubernetes application/tool modules.
- Added Kiali OIDC proxy headers and included the OIDC issuer host in observability egress ServiceEntries.
- Scoped public ServiceEntries to the Istio root namespace and allowed platform-owned waypoint labels on tool namespaces.
- Added OIDC back-channel endpoint overrides for restricted clusters and Argo CD host aliases for internal Keycloak discovery.
- Added OCI NLB `external-ip-only` support on the public Istio Gateway service.
- Added Keycloak-managed platform users, group assignments, and an optional permanent master realm admin user.
- Added explicit Keycloak user required actions so temporary platform users keep `UPDATE_PASSWORD`.
- Added Promtail log collection, Istio PodMonitors, and mesh tracing configuration for Grafana, Loki, Tempo, and Kiali traffic views.
- Raised default Loki ingestion limits for small-cluster bootstrap backfill from Promtail.
- Enabled Tempo metrics-generator by default for Grafana trace metrics and service maps.
- Replaced Istio pod-IP metric scrapes with named metrics Services and ServiceMonitors to reduce `unknown` edges in Kiali when namespaces use an ambient waypoint.
- Labeled the Prometheus pod with `istio.io/dataplane-mode=none` so technical metric scrapes do not appear as application traffic through the ambient waypoint.
- Added ServiceEntries for Keycloak MySQL and observability Object Storage egress, and extended Kiali login token lifetime for long-running graph sessions.

### Decisions

- Keep OCI/IaaS resources in `terraform-oci-modules-af`.
- Keep Helm, Kubernetes manifests, and application providers in this repository.
- Run Keycloak runtime and Keycloak provider configuration in separate phases because the provider authenticates during planning.
- Do not attach Argo CD to MySQL; Argo CD uses Kubernetes as its source of persisted cluster state and Redis as cache.
- Do not request a separate `groups` OAuth scope from Keycloak; group claims are provided by protocol mappers.
- Use the master realm `admin` role for permanent Keycloak administrators on Keycloak 26, where `realm-management` is not present as a client.
