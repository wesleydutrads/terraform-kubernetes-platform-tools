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
    kiali   = string
    grafana = string
    tracing = string
  })
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
    kiali_client_id       = string
    kiali_client_secret   = string
    admin_group           = optional(string, "platform-admins")
    readonly_group        = optional(string, "platform-readonly")
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

variable "enable_tempo" {
  description = "Install Grafana Tempo for traces."
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
