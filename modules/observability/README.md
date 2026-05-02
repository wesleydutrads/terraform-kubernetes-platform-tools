# observability

Installs the observability layer and exposes dashboards through an existing
Gateway API Gateway.

## Components

- Kiali with token authentication
- kube-prometheus-stack with Grafana and Prometheus
- Loki for logs
- Tempo for traces
- optional legacy Jaeger all-in-one
- HTTPRoutes for Kiali, Grafana, and tracing
- optional Istio AuthorizationPolicy requiring a shared `x-monitoring-token` header
- ServiceEntry for public dashboard hostnames to keep Istio/Kiali validation clean
- admin and read-only ServiceAccounts for Kiali token login
- optional Grafana anonymous Viewer mode
- optional Keycloak/OIDC configuration for Grafana and Kiali

## Storage

```mermaid
flowchart TB
  Workloads[Workloads] --> Prom[Prometheus]
  Workloads --> Loki[Loki]
  Workloads --> Tempo[Tempo]
  Prom --> Grafana[Grafana]
  Loki --> Grafana
  Tempo --> Grafana
  Loki --> Obj1[S3-compatible Object Storage]
  Tempo --> Obj2[S3-compatible Object Storage]
  Prom --> Kiali[Kiali]
```

Loki and Tempo are configured for S3-compatible object storage, which works with
OCI Object Storage customer secret keys. This avoids consuming block volume
capacity for logs and traces.

Prometheus can use a PVC with short retention. Grafana persistence is disabled
by default so Always Free block volume capacity remains available for workloads.

## Example

```hcl
module "observability" {
  source = "../modules/observability"

  gateway_name      = module.platform.gateway_name
  gateway_namespace = module.platform.gateway_namespace
  kubeconfig_path   = "~/.kube/config"
  monitoring_token  = random_password.monitoring_token.result

  hosts = {
    kiali   = "kiali.example.com"
    grafana = "grafana.example.com"
    tracing = "tracing.example.com"
  }

  loki_storage = {
    endpoint          = module.observability_storage.s3_endpoint
    region            = "us-phoenix-1"
    bucket_name       = module.observability_storage.buckets.loki.name
    access_key_id     = module.observability_storage.customer_secret_access_key_id
    secret_access_key = module.observability_storage.customer_secret_access_key
  }

  tempo_storage = {
    endpoint          = module.observability_storage.s3_endpoint
    region            = "us-phoenix-1"
    bucket_name       = module.observability_storage.buckets.tempo.name
    access_key_id     = module.observability_storage.customer_secret_access_key_id
    secret_access_key = module.observability_storage.customer_secret_access_key
  }
}
```

## Access

```mermaid
flowchart LR
  User[User] --> GW[Shared Gateway]
  GW --> Apps[Grafana / Kiali / Tracing]
  GW -. optional .-> Token[x-monitoring-token AuthorizationPolicy]
  Token -. invalid .-> Deny[403]
  KialiToken[Kubernetes SA token] --> Kiali[Kiali RBAC]
```

By default, browser access does not require a custom header:

```hcl
enable_monitoring_token_policy = false
```

Set `enable_monitoring_token_policy=true` to require
`x-monitoring-token: <monitoring_token>` at the Gateway.

Kiali still requires a Kubernetes ServiceAccount token when
`kiali_auth_strategy="token"`. The module can create:

- `kiali-admin`, bound to `cluster-admin`
- `kiali-readonly`, bound to the Kiali viewer ClusterRole

Grafana admin login uses the configured admin password. Read-only Grafana access
can be provided through anonymous Viewer mode. When the optional Gateway token
policy is enabled, the request must pass that policy before reaching Grafana,
Kiali, or tracing.

## OIDC

When the Keycloak module is enabled, pass the issuer URL and client secrets
through `oidc`. Grafana uses generic OAuth. Kiali can use
`kiali_auth_strategy="openid"` with the same issuer; in this mode the module
creates the required `kiali` secret containing `oidc-secret`.

## Related Documents

- [Module library README](../../README.md)
- [OKE platform example](../../examples/oke-platform/README.md)
- [Consumer architecture](../../../oci-oke-always-free/docs/architecture.md)
- [Consumer usage guide](../../../oci-oke-always-free/docs/manual-de-uso.md)
- [Platform module](../platform/README.md)
- [Object storage module](../object-storage/README.md)

## References

- [Kiali token authentication](https://kiali.io/docs/configuration/authentication/token/)
- [Kiali OpenID Connect authentication](https://kiali.io/docs/configuration/authentication/openid/)
- [Kiali architecture](https://kiali.io/docs/architecture/architecture/)
- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Grafana Loki storage](https://grafana.com/docs/loki/latest/configure/storage/)
- [Grafana Tempo](https://grafana.com/docs/tempo/latest/)
