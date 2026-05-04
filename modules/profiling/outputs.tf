output "datasource_url" {
  description = "Internal Pyroscope URL for Grafana datasource provisioning."
  value       = var.enabled ? "http://pyroscope.${var.namespace}.svc.cluster.local:4040" : null
}

output "url" {
  description = "Public Pyroscope URL when the route is enabled."
  value       = var.enabled && var.enable_route ? "https://${var.host}" : null
}
