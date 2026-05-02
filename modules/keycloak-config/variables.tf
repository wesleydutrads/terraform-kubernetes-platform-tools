variable "enabled" {
  description = "Manage Keycloak realm and OIDC clients."
  type        = bool
  default     = false
}

variable "realm_name" {
  description = "Realm name for platform applications."
  type        = string
  default     = "platform"
}

variable "admin_group" {
  description = "Group mapped to application admin roles."
  type        = string
  default     = "platform-admins"
}

variable "readonly_group" {
  description = "Group mapped to application read-only roles."
  type        = string
  default     = "platform-readonly"
}

variable "oidc_clients" {
  description = "OIDC clients to create in the platform realm."
  type = map(object({
    redirect_uris = list(string)
    web_origins   = list(string)
    public_client = optional(bool, false)
  }))
  default = {}
}
