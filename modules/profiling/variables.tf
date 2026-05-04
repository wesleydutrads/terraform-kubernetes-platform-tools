variable "enabled" {
  description = "Install Pyroscope and optional public route for Profiles Drilldown."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace where Pyroscope runs."
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

variable "host" {
  description = "Public Pyroscope hostname."
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

variable "istio_root_namespace" {
  description = "Istio root namespace."
  type        = string
  default     = "istio-system"
}

variable "chart_version" {
  description = "Pyroscope Helm chart version."
  type        = string
  default     = "1.18.1"
}

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy Helm chart version."
  type        = string
  default     = "10.4.3"
}

variable "enable_route" {
  description = "Expose Pyroscope through oauth2-proxy and the shared Gateway."
  type        = bool
  default     = false
}

variable "oauth2_proxy" {
  description = "oauth2-proxy settings for the public Pyroscope UI."
  type = object({
    issuer_url    = string
    client_id     = string
    client_secret = string
    cookie_secret = string
  })
  default   = null
  sensitive = true
}

variable "storage" {
  description = "S3-compatible Object Storage settings for Pyroscope."
  type = object({
    endpoint          = string
    region            = string
    bucket_name       = string
    access_key_id     = string
    secret_access_key = string
  })
  default   = null
  sensitive = true
}
