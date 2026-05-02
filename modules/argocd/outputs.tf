output "namespace" {
  description = "Argo CD namespace."
  value       = var.namespace
}

output "host" {
  description = "Argo CD public hostname."
  value       = var.host
}

output "url" {
  description = "Argo CD public URL."
  value       = var.enabled ? "https://${var.host}" : null
}

output "admin_username" {
  description = "Initial Argo CD admin username."
  value       = var.enabled && var.admin_enabled ? "admin" : null
}

output "initial_admin_password_command" {
  description = "Command to read the initial Argo CD admin password."
  value       = var.enabled && var.admin_enabled ? "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" : null
}
