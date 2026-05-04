output "opentelemetry_demo_namespace" {
  description = "Namespace where the OpenTelemetry Demo is deployed when enabled."
  value       = var.enabled && var.enable_opentelemetry_demo ? var.opentelemetry_demo_namespace : null
}

output "opentelemetry_demo_url" {
  description = "Public OpenTelemetry Demo URL when the route is enabled."
  value       = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_demo_route ? "https://${local.opentelemetry_demo_host}" : null
}

output "opentelemetry_load_generator_url" {
  description = "Public OpenTelemetry Demo load-generator URL when the route is enabled."
  value       = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_load_generator_route ? "https://${local.opentelemetry_loadgen_host}" : null
}
