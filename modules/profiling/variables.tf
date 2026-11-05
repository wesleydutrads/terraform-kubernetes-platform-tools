variable "enabled" {
  description = "Install Pyroscope and optional public route for Profiles Drilldown."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace where Pyroscope runs."
  type        = string
  default     = "observability"
}

variable "gateway_name" {
  description = "Gateway API parent name."
  type        = string
}

variable "gateway_namespace" {
  description = "Gateway API parent namespace."
  type        = string
}

variable "host" {
  description = "Public Pyroscope hostname."
  type        = string
}

variable "external_dns_target" {
  description = "Optional public DNS target IP for HTTPRoute records."
  type        = string
  default     = null
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig used by kubectl local-exec resources."
  type        = string
  default     = "~/.kube/config"
}

variable "kubectl_path" {
  description = "kubectl executable path."
  type        = string
  default     = "kubectl"
}

variable "istio_root_namespace" {
  description = "Istio root namespace."
  type        = string
  default     = "istio-system"
}

variable "chart_version" {
  description = "Pyroscope Helm chart version."
  type        = string
  default     = "1.18.1"
}

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy Helm chart version."
  type        = string
  default     = "10.4.3"
}

variable "enable_route" {
  description = "Expose Pyroscope through oauth2-proxy and the shared Gateway."
  type        = bool
  default     = false
}

variable "oauth2_proxy" {
  description = "oauth2-proxy settings for the public Pyroscope UI."
  type = object({
    issuer_url    = string
    client_id     = string
    client_secret = string
    cookie_secret = string
  })
  default   = null
  sensitive = true
}

variable "storage" {
  description = "S3-compatible Object Storage settings for Pyroscope."
  type = object({
    endpoint          = string
    region            = string
    bucket_name       = string
    access_key_id     = string
    secret_access_key = string
  })
  default   = null
  sensitive = true
}

variable "enable_ebpf_lab" {
  description = "Install an official Pyroscope eBPF profiling lab workload for validating Grafana Profiles Drilldown."
  type        = bool
  default     = false
}

variable "ebpf_lab_namespace" {
  description = "Namespace for the Pyroscope eBPF profiling lab."
  type        = string
  default     = "pyroscope-ebpf"
}

variable "ebpf_lab_python_image" {
  description = "Fully qualified Python image used by the CPU profiling lab workload."
  type        = string
  default     = "docker.io/library/python:3.13-slim"
}

variable "ebpf_lab_alloy_image" {
  description = "Fully qualified Grafana Alloy image used by the eBPF profiling lab."
  type        = string
  default     = "docker.io/grafana/alloy:latest"
}

variable "ebpf_lab_use_central_waypoint" {
  description = "Enroll the eBPF lab namespace to use the shared Istio ambient waypoint."
  type        = bool
  default     = false
}

variable "central_egress_waypoint_name" {
  description = "Name of the shared Istio ambient waypoint used by optional lab namespaces."
  type        = string
  default     = "egress-waypoint"
}

variable "enable_go_pprof_lab" {
  description = "Install a Go pprof pull-mode lab for validating CPU, memory, mutex, block, and goroutine profile types."
  type        = bool
  default     = false
}

variable "go_pprof_lab_namespace" {
  description = "Namespace for the Go pprof profiling lab."
  type        = string
  default     = "pyroscope-go-pprof"
}

variable "go_pprof_lab_go_image" {
  description = "Fully qualified Go image used to run the pprof lab workload."
  type        = string
  default     = "docker.io/library/golang:1.25-alpine"
}

variable "go_pprof_lab_alloy_image" {
  description = "Fully qualified Grafana Alloy image used by the Go pprof pull lab."
  type        = string
  default     = "docker.io/grafana/alloy:latest"
}

variable "go_pprof_lab_use_central_waypoint" {
  description = "Enroll the Go pprof lab namespace to use the shared Istio ambient waypoint."
  type        = bool
  default     = false
}

variable "additional_hosts" {
  description = "Opt-in public hostname aliases retained on existing HTTPRoutes and ServiceEntries; primary application and redirect URLs remain unchanged."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for host in var.additional_hosts : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", host)) && strcontains(host, ".")])
    error_message = "Additional hosts must be explicit DNS hostnames without wildcards, schemes or paths."
  }
}

variable "additional_egress_hosts" {
  description = "Opt-in existing OIDC issuer hostname aliases retained in public egress ServiceEntries; does not change issuer or credentials."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for host in var.additional_egress_hosts : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", host)) && strcontains(host, ".")])
    error_message = "Additional egress hosts must be explicit DNS hostnames."
  }
}
