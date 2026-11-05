variable "enabled" {
  description = "Install platform components."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Base DNS zone used by the public gateway and to restrict DNS management."
  type        = string

  validation {
    condition     = trimspace(var.domain_name) != "" && var.domain_name == trimspace(var.domain_name) && !strcontains(var.domain_name, "*")
    error_message = "domain_name must be a nonempty base domain, without whitespace or wildcard."
  }
}

variable "acme_email" {
  description = "ACME account email for Let's Encrypt."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig."
  type        = string
}

variable "kubectl_path" {
  description = "Path to kubectl."
  type        = string
  default     = "kubectl"
}

variable "compartment_ocid" {
  description = "Compartment OCID used by external-dns and DNS01 webhook configuration."
  type        = string
}

variable "region" {
  description = "OCI region."
  type        = string
}

variable "enable_gateway_api_crds" {
  description = "Install Gateway API CRDs."
  type        = bool
  default     = true
}

variable "enable_cert_manager" {
  description = "Install cert-manager."
  type        = bool
  default     = true
}

variable "enable_dns01_oci_webhook" {
  description = "Install the OCI DNS01 cert-manager webhook."
  type        = bool
  default     = true
}

variable "dns01_oci_webhook_image_repository" {
  description = "OCI DNS01 webhook image repository."
  type        = string
  default     = "ghcr.io/giovannicandido/cert-manager-webhook-oci"
}

variable "dns01_oci_webhook_image_tag" {
  description = "OCI DNS01 webhook image tag."
  type        = string
  default     = "build-pipeline"
}

variable "enable_external_dns" {
  description = "Install external-dns."
  type        = bool
  default     = true
}

variable "external_dns_sources" {
  description = "external-dns sources. Include gateway-httproute when the public Gateway has external-dns target annotation."
  type        = list(string)
  default     = ["service", "gateway-httproute"]
}

variable "external_dns_chart_version" {
  description = "external-dns Helm chart version."
  type        = string
  default     = "1.21.1"
}

variable "enable_metrics_server" {
  description = "Install Metrics Server for kubectl top and HPA resource metrics."
  type        = bool
  default     = true
}

variable "enable_istio_ambient" {
  description = "Install Istio ambient components."
  type        = bool
  default     = true
}

variable "enable_istio_tracing" {
  description = "Configure mesh-wide Istio tracing to an OpenTelemetry provider."
  type        = bool
  default     = true
}

variable "istio_tracing_provider_name" {
  description = "Istio Telemetry provider name for mesh tracing."
  type        = string
  default     = "tempo"
}

variable "istio_tracing_service" {
  description = "OpenTelemetry collector service used by Istio tracing."
  type        = string
  default     = "tempo.observability.svc.cluster.local"
}

variable "istio_tracing_port" {
  description = "OpenTelemetry gRPC port used by Istio tracing."
  type        = number
  default     = 4317
}

variable "istio_tracing_sampling_percentage" {
  description = "Istio tracing random sampling percentage."
  type        = number
  default     = 100
}

variable "enable_istio_access_logs" {
  description = "Enable mesh-wide Istio Envoy access logs through the Telemetry API."
  type        = bool
  default     = true
}

variable "istio_access_log_encoding" {
  description = "Istio Envoy access log encoding. Use JSON for Loki/Grafana drilldown parsing."
  type        = string
  default     = "JSON"

  validation {
    condition     = contains(["JSON", "TEXT"], var.istio_access_log_encoding)
    error_message = "istio_access_log_encoding must be JSON or TEXT."
  }
}

variable "enable_public_ingress_gateway" {
  description = "Install public Istio ingress gateway."
  type        = bool
  default     = true
}

variable "enable_central_egress_waypoint" {
  description = "Create a shared ambient waypoint in the Istio root namespace and enroll selected namespaces to use it."
  type        = bool
  default     = false
}

variable "central_egress_waypoint_name" {
  description = "Name of the shared ambient waypoint Gateway."
  type        = string
  default     = "egress-waypoint"
}

variable "central_egress_waypoint_for" {
  description = "Waypoint traffic type. Supported values are service, workload, all, or none."
  type        = string
  default     = "all"

  validation {
    condition     = contains(["service", "workload", "all", "none"], var.central_egress_waypoint_for)
    error_message = "central_egress_waypoint_for must be service, workload, all, or none."
  }
}

variable "central_egress_waypoint_namespaces" {
  description = "Namespaces enrolled to use the shared ambient waypoint."
  type        = list(string)
  default     = ["default"]
}

variable "enable_bookinfo_sample" {
  description = "Deploy the official Istio Bookinfo sample into the default namespace for labs."
  type        = bool
  default     = false
}

variable "enable_bookinfo_route" {
  description = "Create a public HTTPRoute for the Bookinfo productpage service."
  type        = bool
  default     = false
}

variable "bookinfo_host" {
  description = "Optional public hostname for Bookinfo. Defaults to bookinfo.<domain_name>."
  type        = string
  default     = null
}

variable "enable_public_gateway_fallback" {
  description = "Create a low-resource fallback backend and wildcard HTTPRoute so unmatched public hosts are named in Kiali instead of unknown."
  type        = bool
  default     = true
}

variable "public_gateway_fallback_image" {
  description = "Container image used by the public gateway fallback backend."
  type        = string
  default     = "docker.io/nginxinc/nginx-unprivileged:1.27-alpine"
}

variable "public_gateway_allowed_cidrs" {
  description = "CIDRs allowed to reach the public ingress gateway."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_public_gateway_security_headers" {
  description = "Inject baseline browser security headers on all responses served by the public Istio Gateway."
  type        = bool
  default     = true
}

variable "enable_public_gateway_blocked_paths" {
  description = "Deny common scanner and sensitive paths at the public Istio Gateway."
  type        = bool
  default     = true
}

variable "public_gateway_blocked_paths" {
  description = "Path patterns denied at the public Istio Gateway. Istio AuthorizationPolicy path wildcards are supported."
  type        = list(string)
  default = [
    "/.env",
    "/.git*",
    "/wp-admin*",
    "/wp-login.php",
    "/xmlrpc.php",
    "/phpmyadmin*",
    "/server-status",
    "/actuator*",
    "/debug*",
    "/metrics",
  ]
}

variable "enable_public_gateway_local_rate_limit" {
  description = "Enable Envoy local rate limiting on the public Istio Gateway. Disabled by default because it is gateway-wide."
  type        = bool
  default     = false
}

variable "public_gateway_rate_limit_requests_per_minute" {
  description = "Gateway-wide local rate limit budget per public Gateway pod."
  type        = number
  default     = 600

  validation {
    condition     = var.public_gateway_rate_limit_requests_per_minute > 0
    error_message = "public_gateway_rate_limit_requests_per_minute must be greater than zero."
  }
}

variable "enable_wildcard_certificate" {
  description = "Create ClusterIssuer and wildcard Certificate resources."
  type        = bool
  default     = false
}

variable "dns01_webhook_group_name" {
  description = "cert-manager DNS01 webhook group name."
  type        = string
  default     = "acme.d-n.be"
}

variable "dns01_webhook_solver_name" {
  description = "cert-manager DNS01 webhook solver name."
  type        = string
  default     = "oci"
}

variable "dns_provider" {
  description = "DNS provider for cert-manager DNS01 and ExternalDNS. OCI remains the default."
  type        = string
  default     = "oci"

  validation {
    condition     = contains(["oci", "cloudflare"], var.dns_provider)
    error_message = "dns_provider must be oci or cloudflare."
  }
}

variable "cluster_issuer_name" {
  description = "ClusterIssuer name and prefix of its ACME account Secret. Choose a new name when migrating providers to preserve the legacy issuer."
  type        = string
  default     = "letsencrypt-prod"

  validation {
    condition     = length(var.cluster_issuer_name) <= 241 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.cluster_issuer_name))
    error_message = "cluster_issuer_name must be a DNS label of at most 241 characters, leaving room for the account Secret suffix."
  }
}

variable "cloudflare_api_token_secret_name" {
  description = "Existing Secret containing the Cloudflare API token in cert-manager's cluster resource namespace (normally cert-manager). Only the name is managed here, never the token."
  type        = string
  default     = null
}

variable "cloudflare_api_token_secret_key" {
  description = "Key in the existing cert-manager Cloudflare token Secret."
  type        = string
  default     = "api-token"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.cloudflare_api_token_secret_key))
    error_message = "cloudflare_api_token_secret_key must be a nonempty valid Secret data key."
  }
}

variable "external_dns_namespace" {
  description = "Existing namespace of the ExternalDNS release and its token Secret. Changing it migrates the Helm release."
  type        = string
  default     = "kube-system"
}

variable "external_dns_cloudflare_api_token_secret_name" {
  description = "Existing Cloudflare API token Secret in external_dns_namespace. Only the reference is passed to Helm."
  type        = string
  default     = null
}

variable "external_dns_cloudflare_api_token_secret_key" {
  description = "Key in the existing ExternalDNS Cloudflare token Secret."
  type        = string
  default     = "api-token"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.external_dns_cloudflare_api_token_secret_key))
    error_message = "external_dns_cloudflare_api_token_secret_key must be a nonempty valid Secret data key."
  }
}

variable "external_dns_zone_id_filters" {
  description = "Zone IDs ExternalDNS may manage, additionally restricted by domain_name. Required for Cloudflare; empty preserves legacy OCI behavior."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for zone in var.external_dns_zone_id_filters : trimspace(zone) != ""])
    error_message = "external_dns_zone_id_filters cannot contain empty zone IDs."
  }
}

variable "external_dns_txt_owner_id" {
  description = "Unique TXT registry owner ID. Required for Cloudflare; null preserves the chart's legacy default for OCI. Preserve an existing owner ID when adopting its records."
  type        = string
  default     = null
}

variable "external_dns_policy" {
  description = "ExternalDNS record policy. Legacy default is sync; upsert-only is recommended during migration."
  type        = string
  default     = "sync"

  validation {
    condition     = contains(["sync", "upsert-only", "create-only"], var.external_dns_policy)
    error_message = "external_dns_policy must be sync, upsert-only or create-only."
  }
}

variable "preserve_legacy_oci_webhook" {
  description = "Retain the legacy OCI DNS01 webhook while migrating to Cloudflare. Disable only during an explicit decommissioning phase after checking dependent certificates and rollback needs."
  type        = bool
  default     = false
}

variable "external_dns_regex_domain_filter" {
  description = "Optional ExternalDNS regex domain filter. A nonempty regex overrides domainFilters upstream: anchor it and include the exact authorized domain and hostnames explicitly. Zone ID filters still apply."
  type        = string
  default     = null
}

variable "external_dns_cloudflare_proxied" {
  description = "Proxy Cloudflare-managed public A/AAAA/CNAME records by default. Keep true for public application endpoints; per-resource cloudflare-proxied annotations must not disable it. Ignored for OCI."
  type        = bool
  default     = true
}

variable "public_gateway_listener_names" {
  description = "Stable listener names for the primary application domain; retain existing names during coexistence."
  type = object({
    http  = string
    https = string
  })
  default  = { http = "http", https = "https" }
  nullable = false

  validation {
    condition     = alltrue([for name in values(var.public_gateway_listener_names) : length(name) <= 63 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", name))]) && var.public_gateway_listener_names.http != var.public_gateway_listener_names.https
    error_message = "Primary listener names must be distinct Kubernetes section names (1-63 lowercase characters)."
  }
}

variable "additional_application_domains" {
  description = "Opt-in domain aliases. Keys are base domains; values preserve live listener names and reference existing TLS Secrets in istio-system. Does not manage alias certificates, issuers or DNS zones."
  type = map(object({
    http_listener_name  = string
    https_listener_name = optional(string)
    tls_secret_name     = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for domain, alias in var.additional_application_domains :
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", domain)) && strcontains(domain, ".") &&
      can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", alias.http_listener_name)) && length(alias.http_listener_name) <= 63 &&
      ((alias.https_listener_name == null) == (alias.tls_secret_name == null)) &&
      (alias.https_listener_name == null ? true : can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", alias.https_listener_name)) && length(alias.https_listener_name) <= 63) &&
      (alias.tls_secret_name == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", alias.tls_secret_name)))
    ])
    error_message = "Aliases require base DNS domains, valid listener names and either both HTTPS listener and existing TLS Secret or neither."
  }

  validation {
    condition     = length(distinct(flatten([for alias in values(var.additional_application_domains) : compact([alias.http_listener_name, alias.https_listener_name])]))) == length(flatten([for alias in values(var.additional_application_domains) : compact([alias.http_listener_name, alias.https_listener_name])]))
    error_message = "All primary and alias listener names must be unique, including currently disabled HTTPS listeners."
  }
}
