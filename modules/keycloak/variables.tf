variable "enabled" {
  description = "Install Keycloak."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace for Keycloak."
  type        = string
  default     = "keycloak"
}

variable "host" {
  description = "Public hostname for Keycloak."
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
  description = "kubectl executable path."
  type        = string
  default     = "kubectl"
}

variable "image" {
  description = "Keycloak container image."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.6.1"
}

variable "replicas" {
  description = "Keycloak replica count. Keep 1 for Always Free defaults."
  type        = number
  default     = 1
}

variable "admin_username" {
  description = "Initial Keycloak admin username."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Optional initial admin password. If null, the module generates one."
  type        = string
  default     = null
  sensitive   = true
}

variable "database_host" {
  description = "MySQL host or IP address."
  type        = string
  default     = null
}

variable "enable_database_external_name_service" {
  description = "Expose database_host in Kubernetes as a Service type ExternalName."
  type        = bool
  default     = false
}

variable "database_external_name_service_name" {
  description = "Name of the Kubernetes ExternalName Service for the database."
  type        = string
  default     = "mysql"
}

variable "database_port" {
  description = "MySQL port."
  type        = number
  default     = 3306
}

variable "database_admin_username" {
  description = "MySQL admin username used by the bootstrap Job."
  type        = string
  default     = null
}

variable "database_admin_password" {
  description = "MySQL admin password used by the bootstrap Job."
  type        = string
  default     = null
  sensitive   = true
}

variable "database_name" {
  description = "MySQL database name for Keycloak."
  type        = string
  default     = "keycloak"
}

variable "database_username" {
  description = "MySQL application username for Keycloak."
  type        = string
  default     = "keycloak"
}

variable "database_password" {
  description = "Optional MySQL application password. If null, the module generates one."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_ambient" {
  description = "Label the namespace for Istio ambient mode."
  type        = bool
  default     = true
}

variable "enable_public_host_service_entry" {
  description = "Create a ServiceEntry for the public Keycloak hostname."
  type        = bool
  default     = true
}

variable "external_dns_target" {
  description = "Optional public DNS target IP for HTTPRoute records."
  type        = string
  default     = null
}

variable "resources" {
  description = "Keycloak resource requests and limits."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "750m"
      memory = "1024Mi"
    }
  }
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

variable "hostname_url" {
  description = "Explicit Keycloak frontend URL, independent of route hostname; null uses https://host. Preserve the deployed value during additive domain coexistence."
  type        = string
  default     = null

  validation {
    condition     = var.hostname_url == null ? true : can(regex("^https://[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.hostname_url))
    error_message = "hostname_url must be null or an HTTPS origin without path."
  }
}
