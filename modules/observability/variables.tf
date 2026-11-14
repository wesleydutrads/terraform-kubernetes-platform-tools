variable "enabled" {
  description = "Install observability components."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for observability components."
  type        = string
  default     = "observability"
}

variable "gateway_name" {
  description = "Gateway API parent name."
  type        = string
}

variable "gateway_namespace" {
  description = "Gateway API parent namespace."
  type        = string
}

variable "hosts" {
  description = "Dashboard hostnames."
  type = object({
    kiali      = string
    grafana    = string
    tracing    = string
    prometheus = optional(string)
  })
}

variable "oauth2_proxy" {
  description = "Optional oauth2-proxy settings for dashboards without native browser authentication."
  type = object({
    issuer_url    = string
    client_id     = string
    client_secret = string
    cookie_secret = string
  })
  default   = null
  sensitive = true
}

variable "monitoring_token" {
  description = "Shared token used when the optional Istio AuthorizationPolicy is enabled."
  type        = string
  sensitive   = true
}

variable "enable_monitoring_token_policy" {
  description = "Create an Istio AuthorizationPolicy requiring x-monitoring-token on public monitoring hosts. Keep false when browser access must not depend on custom headers."
  type        = bool
  default     = false
}

variable "enable_public_host_service_entries" {
  description = "Create ServiceEntry resources for public monitoring hostnames referenced by HTTPRoutes and optional AuthorizationPolicy."
  type        = bool
  default     = true
}

variable "external_dns_target" {
  description = "Optional public DNS target IP for HTTPRoute records. Use this when Gateway status exposes both private and public addresses."
  type        = string
  default     = null
}

variable "kiali_auth_strategy" {
  description = "Kiali authentication strategy. Use token for Kubernetes ServiceAccount token login."
  type        = string
  default     = "token"

  validation {
    condition     = contains(["anonymous", "token", "openid"], var.kiali_auth_strategy)
    error_message = "Supported Kiali auth strategies in this module are anonymous, token, and openid."
  }
}

variable "oidc" {
  description = "Optional OIDC configuration shared by Grafana and Kiali."
  type = object({
    issuer_url            = string
    grafana_client_id     = string
    grafana_client_secret = string
    grafana_auth_url      = optional(string)
    grafana_token_url     = optional(string)
    grafana_api_url       = optional(string)
    kiali_client_id       = string
    kiali_client_secret   = string
    kiali_discovery_override = optional(object({
      authorization_endpoint = optional(string)
      jwks_uri               = optional(string)
      token_endpoint         = optional(string)
      userinfo_endpoint      = optional(string)
    }))
    admin_group    = optional(string, "platform-admins")
    readonly_group = optional(string, "platform-readonly")
  })
  default = null
}

variable "istio_root_namespace" {
  description = "Istio root namespace used by Kiali."
  type        = string
  default     = "istio-system"
}

variable "enable_monitoring_access_rbac" {
  description = "Create admin and read-only ServiceAccounts for Kiali token login."
  type        = bool
  default     = true
}

variable "kiali_admin_service_account_name" {
  description = "ServiceAccount name for full-admin Kiali access."
  type        = string
  default     = "kiali-admin"
}

variable "kiali_readonly_service_account_name" {
  description = "ServiceAccount name for read-only Kiali access."
  type        = string
  default     = "kiali-readonly"
}

variable "kiali_login_token_expiration_seconds" {
  description = "Kiali login token lifetime. Increase this for long observation sessions in the Kiali UI."
  type        = number
  default     = 604800
}

variable "enable_grafana_anonymous_viewer" {
  description = "Enable Grafana anonymous Viewer access. If enable_monitoring_token_policy=true, this remains behind the shared Gateway token."
  type        = bool
  default     = true
}

variable "enable_grafana_persistence" {
  description = "Enable a PVC for Grafana. Keep false for Always Free defaults."
  type        = bool
  default     = false
}

variable "enable_prometheus_persistence" {
  description = "Enable a PVC for Prometheus."
  type        = bool
  default     = true
}

variable "enable_prometheus_route" {
  description = "Expose the Prometheus UI through oauth2-proxy and the shared Gateway."
  type        = bool
  default     = false
}

variable "enable_profiles_drilldown" {
  description = "Install Grafana Profiles Drilldown support and provision a Pyroscope datasource when pyroscope_datasource_url is set."
  type        = bool
  default     = false
}

variable "pyroscope_datasource_url" {
  description = "Internal Pyroscope datasource URL for Grafana Profiles Drilldown."
  type        = string
  default     = null
}

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy Helm chart version."
  type        = string
  default     = "10.4.3"
}

variable "monitoring_storage_class_name" {
  description = "StorageClass used by monitoring PVCs. Null uses the cluster default."
  type        = string
  default     = null
}

variable "grafana_storage_size" {
  description = "Grafana PVC size."
  type        = string
  default     = "5Gi"
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC size."
  type        = string
  default     = "20Gi"
}

variable "enable_loki" {
  description = "Install Loki for logs."
  type        = bool
  default     = true
}

variable "enable_loki_pattern_ingester" {
  description = "Enable Loki pattern ingester so Grafana can detect repeated log patterns in Logs Drilldown."
  type        = bool
  default     = true
}

variable "enable_promtail" {
  description = "Install Promtail as a node log collector that ships Kubernetes pod logs to Loki."
  type        = bool
  default     = true
}

variable "enable_tempo" {
  description = "Install Grafana Tempo for traces."
  type        = bool
  default     = true
}

variable "enable_opentelemetry_operator" {
  description = "Install the OpenTelemetry Operator for auto-instrumentation and Collector CRDs."
  type        = bool
  default     = false
}

variable "opentelemetry_operator_chart_version" {
  description = "OpenTelemetry Operator Helm chart version."
  type        = string
  default     = "0.111.0"
}

variable "enable_opentelemetry_collector_gateway" {
  description = "Install an OpenTelemetry Collector gateway that receives application OTLP telemetry and forwards it to Tempo, Prometheus, and Loki."
  type        = bool
  default     = false
}

variable "opentelemetry_collector_chart_version" {
  description = "OpenTelemetry Collector Helm chart version."
  type        = string
  default     = "0.153.0"
}

variable "opentelemetry_collector_name" {
  description = "Name for the shared OpenTelemetry Collector gateway service."
  type        = string
  default     = "otel-collector"
}

variable "enable_opentelemetry_instrumentation" {
  description = "Create an OpenTelemetry Instrumentation CR for Kubernetes auto-instrumentation."
  type        = bool
  default     = false
}

variable "opentelemetry_instrumentation_name" {
  description = "Name of the OpenTelemetry Instrumentation CR."
  type        = string
  default     = "platform"
}

variable "enable_tempo_metrics_generator" {
  description = "Enable Tempo metrics-generator so Grafana can query trace-derived metrics and service maps."
  type        = bool
  default     = true
}

variable "enable_istio_pod_monitors" {
  description = "Create Istio metrics Services and monitors for the control plane, gateways, waypoints, and ztunnel so Kiali can render traffic."
  type        = bool
  default     = true
}

variable "loki_storage" {
  description = "S3-compatible storage settings for Loki. Required when enable_loki=true."
  type = object({
    endpoint          = string
    region            = string
    bucket_name       = string
    access_key_id     = string
    secret_access_key = string
  })
  sensitive = true
  default   = null
}

variable "tempo_storage" {
  description = "S3-compatible storage settings for Tempo. Required when enable_tempo=true."
  type = object({
    endpoint          = string
    region            = string
    bucket_name       = string
    access_key_id     = string
    secret_access_key = string
  })
  sensitive = true
  default   = null
}

variable "loki_retention_period" {
  description = "Log retention period managed by Loki."
  type        = string
  default     = "72h"
}

variable "loki_ingestion_rate_mb" {
  description = "Per-tenant Loki ingestion rate limit in MB/s."
  type        = number
  default     = 16
}

variable "loki_ingestion_burst_size_mb" {
  description = "Per-tenant Loki ingestion burst size in MB."
  type        = number
  default     = 32
}

variable "tempo_retention_period" {
  description = "Trace retention period managed by Tempo."
  type        = string
  default     = "24h"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig."
  type        = string
}

variable "kubectl_path" {
  description = "Path to kubectl."
  type        = string
  default     = "kubectl"
}

variable "enable_kiali" {
  description = "Install Kiali."
  type        = bool
  default     = true
}

variable "enable_prometheus_stack" {
  description = "Install kube-prometheus-stack."
  type        = bool
  default     = true
}

variable "enable_jaeger" {
  description = "Install legacy Jaeger all-in-one instead of Tempo."
  type        = bool
  default     = false
}

variable "additional_hosts" {
  description = "Opt-in public hostname aliases retained on existing HTTPRoutes and ServiceEntries; primary application and redirect URLs remain unchanged."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for host in flatten(values(var.additional_hosts)) : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", host)) && strcontains(host, ".")])
    error_message = "Additional hosts must be explicit DNS hostnames without wildcards, schemes or paths."
  }
}

variable "additional_egress_hosts" {
  description = "Opt-in existing OIDC issuer hostname aliases retained in public egress ServiceEntries; does not change issuer or credentials."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for host in var.additional_egress_hosts : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", host)) && strcontains(host, ".")])
    error_message = "Additional egress hosts must be explicit DNS hostnames."
  }
}

variable "kiali_chart_version" {
  description = "Optional explicit version; pin during reconciliation to avoid incidental chart upgrades."
  type        = string
  default     = null
}

variable "prometheus_stack_chart_version" {
  description = "Optional explicit version; pin during reconciliation to avoid incidental chart upgrades."
  type        = string
  default     = null
}
