variable "enabled" {
  description = "Install lab applications."
  type        = bool
  default     = true
}

variable "gateway_name" {
  description = "Gateway API parent name."
  type        = string
}

variable "gateway_namespace" {
  description = "Gateway API parent namespace."
  type        = string
}

variable "external_dns_target" {
  description = "Optional public DNS target IP for HTTPRoute records."
  type        = string
  default     = null
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig used by kubectl local-exec resources."
  type        = string
  default     = "~/.kube/config"
}

variable "kubectl_path" {
  description = "kubectl executable path."
  type        = string
  default     = "kubectl"
}

variable "hosts" {
  description = "Lab application hostnames."
  type = object({
    grafana               = string
    opentelemetry_demo    = optional(string)
    opentelemetry_loadgen = optional(string)
  })
}

variable "oauth2_proxy" {
  description = "Optional oauth2-proxy settings for lab UIs without native browser authentication."
  type = object({
    issuer_url    = string
    client_id     = string
    client_secret = string
    cookie_secret = string
  })
  default   = null
  sensitive = true
}

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy Helm chart version."
  type        = string
  default     = "10.4.3"
}

variable "istio_root_namespace" {
  description = "Istio root namespace."
  type        = string
  default     = "istio-system"
}

variable "central_egress_waypoint_name" {
  description = "Name of the shared Istio ambient waypoint used by lab namespaces."
  type        = string
  default     = "egress-waypoint"
}

variable "enable_bookinfo_opentelemetry_annotations" {
  description = "Annotate supported Bookinfo deployments for OpenTelemetry Operator auto-instrumentation."
  type        = bool
  default     = false
}

variable "opentelemetry_instrumentation_ref" {
  description = "Namespace/name reference for OpenTelemetry auto-instrumentation annotations."
  type        = string
  default     = null
}

variable "opentelemetry_collector_endpoint" {
  description = "Internal OTLP HTTP endpoint for application telemetry."
  type        = string
  default     = null
}

variable "enable_opentelemetry_demo" {
  description = "Install the official OpenTelemetry Demo application for observability labs."
  type        = bool
  default     = false
}

variable "opentelemetry_demo_use_central_waypoint" {
  description = "Enroll the OpenTelemetry Demo namespace to use the shared Istio ambient waypoint."
  type        = bool
  default     = true
}

variable "opentelemetry_demo_chart_version" {
  description = "OpenTelemetry Demo Helm chart version."
  type        = string
  default     = "0.40.7"
}

variable "opentelemetry_demo_namespace" {
  description = "Namespace for the OpenTelemetry Demo application."
  type        = string
  default     = "otel-demo"
}

variable "opentelemetry_demo_host" {
  description = "Optional public hostname for the OpenTelemetry Demo frontend."
  type        = string
  default     = null
}

variable "opentelemetry_demo_enable_browser_traffic" {
  description = "Enable Playwright browser users in the OpenTelemetry Demo load generator."
  type        = bool
  default     = false
}

variable "opentelemetry_demo_accounting_memory_limit" {
  description = "Memory limit for the OpenTelemetry Demo accounting service."
  type        = string
  default     = "256Mi"
}

variable "enable_opentelemetry_demo_route" {
  description = "Create a public HTTPRoute for the OpenTelemetry Demo frontend."
  type        = bool
  default     = false
}

variable "enable_opentelemetry_load_generator_route" {
  description = "Expose the OpenTelemetry Demo Locust load-generator UI through oauth2-proxy and the shared Gateway."
  type        = bool
  default     = false
}
