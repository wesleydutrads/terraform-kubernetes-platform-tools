output "namespace" {
  description = "Observability namespace."
  value       = var.namespace
}

output "hosts" {
  description = "Dashboard hostnames."
  value       = var.hosts
}

output "kiali_service_name" {
  description = "Kiali service name."
  value       = "kiali"
}

output "grafana_service_name" {
  description = "Grafana service name."
  value       = "monitoring-grafana"
}

output "tracing_service_name" {
  description = "Tracing service name."
  value       = var.enable_tempo ? "monitoring-grafana" : "jaeger"
}

output "loki_service_name" {
  description = "Loki gateway service name."
  value       = "loki-gateway"
}

output "kiali_admin_token_command" {
  description = "Command to create a short-lived ServiceAccount token for full-admin Kiali access."
  value       = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? "kubectl -n ${var.namespace} create token ${var.kiali_admin_service_account_name}" : null
}

output "kiali_readonly_token_command" {
  description = "Command to create a short-lived ServiceAccount token for read-only Kiali access."
  value       = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? "kubectl -n ${var.namespace} create token ${var.kiali_readonly_service_account_name}" : null
}

output "grafana_admin_username" {
  description = "Grafana admin username."
  value       = var.enabled && var.enable_prometheus_stack ? "admin" : null
}

output "grafana_readonly_mode" {
  description = "Grafana read-only access mode."
  value       = var.enabled && var.enable_prometheus_stack && var.enable_grafana_anonymous_viewer ? (var.enable_monitoring_token_policy ? "anonymous-viewer-behind-shared-gateway-token" : "anonymous-viewer") : null
}
