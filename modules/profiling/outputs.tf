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

output "go_pprof_lab_namespace" {
  description = "Namespace where the Go pprof profiling lab is deployed."
  value       = var.enabled && var.enable_go_pprof_lab ? var.go_pprof_lab_namespace : null
}

output "go_pprof_lab_service_name" {
  description = "Pyroscope service_name emitted by the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "pyroscope-go/go-pprof-lab" : null
}

output "go_pprof_lab_cpu_render_query" {
  description = "Pyroscope CPU render API query for validating the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name=\"pyroscope-go/go-pprof-lab\"}" : null
}

output "go_pprof_lab_memory_render_query" {
  description = "Pyroscope heap memory render API query for validating the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "memory:alloc_space:bytes:space:bytes{service_name=\"pyroscope-go/go-pprof-lab\"}" : null
}

output "go_pprof_lab_goroutine_render_query" {
  description = "Pyroscope goroutine render API query for validating the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "goroutine:goroutine:count:goroutine:count{service_name=\"pyroscope-go/go-pprof-lab\"}" : null
}

output "go_pprof_lab_mutex_render_query" {
  description = "Pyroscope mutex contention render API query for validating the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "mutex:contentions:count:contentions:count{service_name=\"pyroscope-go/go-pprof-lab\"}" : null
}

output "go_pprof_lab_block_render_query" {
  description = "Pyroscope block contention render API query for validating the Go pprof profiling lab."
  value       = var.enabled && var.enable_go_pprof_lab ? "block:contentions:count:contentions:count{service_name=\"pyroscope-go/go-pprof-lab\"}" : null
}
