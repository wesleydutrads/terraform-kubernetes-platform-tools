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

variable "host_aliases" {
  description = "Optional host aliases injected into Argo CD pods, useful for internal OIDC provider routing."
  type = list(object({
    ip        = string
    hostnames = list(string)
  }))
  default = []
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

variable "additional_hosts" {
  description = "Opt-in public hostname aliases retained on existing HTTPRoutes and ServiceEntries; primary application and redirect URLs remain unchanged."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for host in var.additional_hosts : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", host)) && strcontains(host, ".")])
    error_message = "Additional hosts must be explicit DNS hostnames without wildcards, schemes or paths."
  }
}

variable "url" {
  type        = string
  default     = null
  description = "URL canônica explícita, sem alterar o host ou as rotas; null usa https://host."
  validation {
    condition     = var.url == null ? true : can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$", var.url))
    error_message = "Informe URL HTTPS sem credenciais ou espaços."
  }
}
