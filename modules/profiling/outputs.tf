output "datasource_url" {
  description = "Internal Pyroscope URL for Grafana datasource provisioning."
  value       = var.enabled ? "http://pyroscope.${var.namespace}.svc.cluster.local:4040" : null
}

output "url" {
  description = "Public Pyroscope URL when the route is enabled."
  value       = var.enabled && var.enable_route ? "https://${var.host}" : null
}

output "ebpf_lab_namespace" {
  description = "Namespace where the Pyroscope eBPF profiling lab is deployed."
  value       = var.enabled && var.enable_ebpf_lab ? var.ebpf_lab_namespace : null
}

output "ebpf_lab_service_name" {
  description = "Pyroscope service_name emitted by the eBPF profiling lab."
  value       = var.enabled && var.enable_ebpf_lab ? "pyroscope-ebpf/python-fast-slow" : null
}

output "ebpf_lab_render_query" {
  description = "Pyroscope render API query for validating the eBPF profiling lab."
  value       = var.enabled && var.enable_ebpf_lab ? "process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name=\"pyroscope-ebpf/python-fast-slow\"}" : null
}
