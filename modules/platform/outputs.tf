output "istio_namespace" {
  description = "Istio namespace."
  value       = local.istio_namespace
}

output "wildcard_secret_name" {
  description = "Wildcard TLS secret name expected by the public Gateway."
  value       = local.wildcard_secret_name
}

output "gateway_name" {
  description = "Public Gateway API object name."
  value       = "public"
}

output "gateway_namespace" {
  description = "Public Gateway API object namespace."
  value       = local.istio_namespace
}

output "gateway_service_name" {
  description = "Istio-managed LoadBalancer Service name for the public Gateway."
  value       = "public-istio"
}

output "central_egress_waypoint_name" {
  description = "Shared ambient waypoint name."
  value       = var.enable_central_egress_waypoint ? var.central_egress_waypoint_name : null
}

output "central_egress_waypoint_namespace" {
  description = "Shared ambient waypoint namespace."
  value       = var.enable_central_egress_waypoint ? local.istio_namespace : null
}

output "central_egress_waypoint_namespaces" {
  description = "Namespaces enrolled to use the shared ambient waypoint."
  value       = var.enable_central_egress_waypoint ? var.central_egress_waypoint_namespaces : []
}

output "bookinfo_namespace" {
  description = "Namespace where Bookinfo is deployed."
  value       = var.enable_bookinfo_sample ? "default" : null
}

output "bookinfo_host" {
  description = "Public Bookinfo hostname when the route is enabled."
  value       = var.enable_bookinfo_sample && var.enable_bookinfo_route ? local.bookinfo_host : null
}

output "bookinfo_url" {
  description = "Public Bookinfo URL when the route is enabled."
  value       = var.enable_bookinfo_sample && var.enable_bookinfo_route ? "https://${local.bookinfo_host}/productpage" : null
}
