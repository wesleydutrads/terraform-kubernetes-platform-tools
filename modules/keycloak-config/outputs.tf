output "issuer_url" {
  description = "Relative OIDC issuer path for the managed realm."
  value       = var.enabled ? "/realms/${var.realm_name}" : null
}

output "realm_name" {
  description = "Managed realm name."
  value       = var.enabled ? var.realm_name : null
}

output "client_ids" {
  description = "OIDC client IDs managed by this module."
  value       = var.enabled ? keys(var.oidc_clients) : []
}

output "client_secrets" {
  description = "Client secrets for confidential OIDC clients."
  value = var.enabled ? {
    for name, client in keycloak_openid_client.this : name => client.client_secret
  } : {}
  sensitive = true
}
