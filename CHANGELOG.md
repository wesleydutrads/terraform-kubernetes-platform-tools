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
- Added a named public gateway fallback backend so unmatched wildcard hosts appear as `public-fallback` instead of `unknown` in Kiali.
- Kept the Kiali login token signing key stable across Helm upgrades to avoid forced session invalidation.
- Exported shared Istio ServiceEntries mesh-wide so ambient namespaces can resolve named public, Object Storage, and MySQL egress destinations.
- Added a dedicated `lab-apps` module for OpenTelemetry Demo and Bookinfo auto-instrumentation labs.
- Added Keycloak database `ExternalName` Service support and DNS-based
  ServiceEntry generation for MySQL private DNS names.
- Removed the non-existent `groups` OAuth scope from oauth2-proxy clients while
  keeping group claims available through Keycloak protocol mappers.
- Disabled Pyroscope internal self-profiling so the Alloy pprof scraper remains
  the single profile collector for the Pyroscope process.
- Fixed Grafana Tempo trace-to-profiles provisioning to use the `${__tags}`
  matcher instead of an interpolated empty `service_name` value.
- Added Kubernetes metadata enrichment to the OpenTelemetry Collector gateway so
  traces and logs carry namespace, pod, deployment, node, container, image,
  service, and version attributes without duplicating Prometheus metric labels.
- Added Bookinfo observability labels and OpenTelemetry resource annotations to
  align traces, logs, metrics, and future profiles with the same service names.
- Added shared OpenTelemetry resource attributes to the OpenTelemetry Demo so
  exported telemetry consistently identifies the lab environment and cluster.
- Added an optional official Grafana Pyroscope eBPF Kubernetes lab with a
  CPU-bound Python workload and Alloy DaemonSet for validating Profiles
  Drilldown with real profile data.
- Added an optional Go pprof pull-mode profiling lab to validate runtime
  profile types such as CPU, memory, mutex, block, and goroutine through
  Grafana Alloy and Pyroscope.
- Added optional no-cost public Istio Gateway hardening with browser security
  headers, scanner path denial, and opt-in local rate limiting.

### Decisions

- Keep OCI/IaaS resources in `terraform-oci-modules-af`.
- Keep Helm, Kubernetes manifests, and application providers in this repository.
- Keep lab workloads separate from core observability so production stacks can reuse monitoring without sample applications.
- Run Keycloak runtime and Keycloak provider configuration in separate phases because the provider authenticates during planning.
- Do not attach Argo CD to MySQL; Argo CD uses Kubernetes as its source of persisted cluster state and Redis as cache.
- Do not request a separate `groups` OAuth scope from Keycloak; group claims are provided by protocol mappers.
- Use the master realm `admin` role for permanent Keycloak administrators on Keycloak 26, where `realm-management` is not present as a client.
- Keep Keycloak connected to the OCI MySQL private DNS FQDN directly while
  exposing the same database to the cluster through an optional Kubernetes
  `ExternalName` Service. Routing Keycloak itself through Kubernetes service
  indirection can fail during JVM startup if the service FQDN is not resolvable
  early enough.
