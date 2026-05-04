output "url" {
  description = "Keycloak public URL."
  value       = var.enabled ? "https://${var.host}" : null
}

output "issuer_url" {
  description = "Default master realm URL. Application issuers are managed by keycloak-config."
  value       = var.enabled ? "https://${var.host}/realms/master" : null
}

output "admin_username" {
  description = "Keycloak admin username."
  value       = var.enabled ? var.admin_username : null
}

output "admin_password" {
  description = "Keycloak admin password."
  value       = var.enabled ? local.admin_password : null
  sensitive   = true
}

output "database_name" {
  description = "Keycloak MySQL database name."
  value       = var.enabled ? var.database_name : null
}

output "database_username" {
  description = "Keycloak MySQL application username."
  value       = var.enabled ? var.database_username : null
}

output "database_internal_fqdn" {
  description = "Internal database host used by Keycloak."
  value       = var.enabled && var.database_host != null ? local.database_host : null
}

output "database_external_name_target" {
  description = "ExternalName target for the optional database service."
  value       = var.enabled && var.database_host != null && var.enable_database_external_name_service ? var.database_host : null
}
