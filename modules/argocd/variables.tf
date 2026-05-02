variable "enabled" {
  description = "Install Argo CD."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace for Argo CD."
  type        = string
  default     = "argocd"
}

variable "host" {
  description = "Public hostname for Argo CD."
  type        = string
}

variable "gateway_name" {
  description = "Gateway API parent name."
  type        = string
}

variable "gateway_namespace" {
  description = "Gateway API parent namespace."
  type        = string
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

variable "chart_version" {
  description = "Optional argo-cd Helm chart version. Null uses the repository default/latest available during install."
  type        = string
  default     = null
}

variable "enable_ambient" {
  description = "Label the namespace for Istio ambient mode."
  type        = bool
  default     = true
}

variable "enable_public_host_service_entry" {
  description = "Create a ServiceEntry for the public Argo CD hostname."
  type        = bool
  default     = true
}

variable "external_dns_target" {
  description = "Optional public DNS target IP for HTTPRoute records."
  type        = string
  default     = null
}

variable "admin_enabled" {
  description = "Keep the built-in Argo CD admin user enabled until OIDC is configured."
  type        = bool
  default     = true
}

variable "oidc" {
  description = "Optional OIDC configuration for Argo CD."
  type = object({
    issuer_url     = string
    client_id      = string
    client_secret  = string
    admin_group    = optional(string, "platform-admins")
    readonly_group = optional(string, "platform-readonly")
  })
  default = null
}
