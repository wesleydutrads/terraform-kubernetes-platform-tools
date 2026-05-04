# profiling

Installs Grafana Pyroscope for continuous profiling and exposes the UI through
`oauth2-proxy` when requested.

## Architecture

```mermaid
flowchart LR
  User[Browser] --> Gateway[Istio public Gateway]
  Gateway --> Proxy[oauth2-proxy]
  Proxy --> Keycloak[Keycloak OIDC]
  Proxy --> Pyroscope[Pyroscope]
  Grafana[Grafana Profiles Drilldown] --> Pyroscope
  Pyroscope --> ObjectStorage[(OCI Object Storage S3)]
  Workloads[Profiled workloads] --> Pyroscope
```

## Notes

- Use single-binary Pyroscope for Always Free clusters.
- Keep the public UI behind Keycloak; Pyroscope has no native OIDC login.
- Use Object Storage for profile blocks to avoid consuming block volume quota.
- Profile data only appears for workloads that expose profiles or push data.
