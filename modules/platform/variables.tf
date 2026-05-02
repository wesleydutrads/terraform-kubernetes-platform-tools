variable "enabled" {
  description = "Install platform components."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Base DNS zone used by the public gateway."
  type        = string
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

variable "public_gateway_allowed_cidrs" {
  description = "CIDRs allowed to reach the public ingress gateway."
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
