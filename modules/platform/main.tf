locals {
  kubeconfig_path      = pathexpand(var.kubeconfig_path)
  istio_namespace      = "istio-system"
  wildcard_secret_name = "wildcard-${replace(var.domain_name, ".", "-")}-tls"
  bookinfo_host        = coalesce(var.bookinfo_host, "bookinfo.${var.domain_name}")
  application_domains  = distinct(concat([var.domain_name], keys(var.additional_application_domains)))
  bookinfo_hosts       = distinct(concat([local.bookinfo_host], [for domain in keys(var.additional_application_domains) : "bookinfo.${domain}"]))
  letsencrypt_prod_manifest = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = var.cluster_issuer_name }
    spec = {
      acme = {
        email               = var.acme_email
        server              = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = { name = "${var.cluster_issuer_name}-account-key" }
        solvers = [{
          selector = { dnsZones = [var.domain_name] }
          dns01 = merge(var.dns_provider == "cloudflare" ? {
            cloudflare = {
              apiTokenSecretRef = {
                name = var.cloudflare_api_token_secret_name
                key  = var.cloudflare_api_token_secret_key
              }
            }
            } : {}, var.dns_provider == "oci" ? {
            webhook = {
              groupName  = var.dns01_webhook_group_name
              solverName = var.dns01_webhook_solver_name
              config = {
                compartmentOCID = var.compartment_ocid
                region          = var.region
              }
            }
          } : {})
        }]
      }
    }
  })
  wildcard_certificate_manifest            = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: wildcard-${replace(var.domain_name, ".", "-")}
      namespace: ${local.istio_namespace}
    spec:
      secretName: ${local.wildcard_secret_name}
      issuerRef:
        name: ${var.cluster_issuer_name}
        kind: ClusterIssuer
      dnsNames:
        - ${var.domain_name}
        - "*.${var.domain_name}"
    YAML
  public_gateway_manifest                  = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: public
      namespace: ${local.istio_namespace}
    spec:
      infrastructure:
        annotations:
          oci.oraclecloud.com/load-balancer-type: nlb
          oci-network-load-balancer.oraclecloud.com/external-ip-only: "true"
        parametersRef:
          group: ""
          kind: ConfigMap
          name: public-gateway-options
      gatewayClassName: istio
      listeners:
        - name: ${var.public_gateway_listener_names.http}
          hostname: "*.${var.domain_name}"
          port: 80
          protocol: HTTP
          allowedRoutes:
            namespaces:
              from: All
%{if var.enable_wildcard_certificate~}
        - name: ${var.public_gateway_listener_names.https}
          hostname: "*.${var.domain_name}"
          port: 443
          protocol: HTTPS
          tls:
            mode: Terminate
            certificateRefs:
              - name: ${local.wildcard_secret_name}
          allowedRoutes:
            namespaces:
              from: All
%{endif~}
%{for domain, alias in var.additional_application_domains~}
        - name: ${alias.http_listener_name}
          hostname: "*.${domain}"
          port: 80
          protocol: HTTP
          allowedRoutes:
            namespaces:
              from: All
%{if alias.https_listener_name != null~}
        - name: ${alias.https_listener_name}
          hostname: "*.${domain}"
          port: 443
          protocol: HTTPS
          tls:
            mode: Terminate
            certificateRefs:
              - name: ${alias.tls_secret_name}
          allowedRoutes:
            namespaces:
              from: All
%{endif~}
%{endfor~}
    YAML
  public_gateway_fallback_manifest         = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: public-fallback-nginx
      namespace: ${local.istio_namespace}
    data:
      default.conf: |
        server {
          listen 8080;
          server_name _;
          location / {
            add_header Content-Type text/plain always;
            add_header X-Content-Type-Options nosniff always;
            add_header Referrer-Policy no-referrer always;
            add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
            add_header X-Robots-Tag "noindex, nofollow" always;
            return 404 "No route configured for this host.\n";
          }
        }
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: public-fallback
      namespace: ${local.istio_namespace}
      labels:
        app: public-fallback
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: public-fallback
      template:
        metadata:
          labels:
            app: public-fallback
            service.istio.io/canonical-name: public-fallback
        spec:
          containers:
            - name: nginx
              image: ${var.public_gateway_fallback_image}
              ports:
                - name: http
                  containerPort: 8080
              resources:
                requests:
                  cpu: 5m
                  memory: 16Mi
                limits:
                  memory: 64Mi
              volumeMounts:
                - name: config
                  mountPath: /etc/nginx/conf.d
                  readOnly: true
          volumes:
            - name: config
              configMap:
                name: public-fallback-nginx
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: public-fallback
      namespace: ${local.istio_namespace}
      labels:
        app: public-fallback
    spec:
      selector:
        app: public-fallback
      ports:
        - name: http
          port: 80
          targetPort: 8080
    ---
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: public-fallback
      namespace: ${local.istio_namespace}
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: fallback
        platform.arcanjoconsultoria.com.br/auth: none
    spec:
      parentRefs:
        - name: public
          namespace: ${local.istio_namespace}
      hostnames:
    %{for domain in local.application_domains}
        - "*.${domain}"
    %{endfor}
      rules:
        - backendRefs:
            - name: public-fallback
              port: 80
    YAML
  public_gateway_security_headers_manifest = <<-YAML
    apiVersion: networking.istio.io/v1alpha3
    kind: EnvoyFilter
    metadata:
      name: public-gateway-security-headers
      namespace: ${local.istio_namespace}
    spec:
      workloadSelector:
        labels:
          gateway.networking.k8s.io/gateway-name: public
      configPatches:
        - applyTo: HTTP_FILTER
          match:
            context: GATEWAY
            listener:
              filterChain:
                filter:
                  name: envoy.filters.network.http_connection_manager
                  subFilter:
                    name: envoy.filters.http.router
          patch:
            operation: INSERT_BEFORE
            value:
              name: envoy.filters.http.lua
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                inlineCode: |
                  local function set_if_absent(headers, name, value)
                    if headers:get(name) == nil then
                      headers:add(name, value)
                    end
                  end

                  function envoy_on_response(response_handle)
                    local headers = response_handle:headers()
                    set_if_absent(headers, "strict-transport-security", "max-age=31536000; includeSubDomains")
                    set_if_absent(headers, "x-content-type-options", "nosniff")
                    set_if_absent(headers, "referrer-policy", "strict-origin-when-cross-origin")
                    set_if_absent(headers, "permissions-policy", "geolocation=(), microphone=(), camera=()")
                    set_if_absent(headers, "x-frame-options", "SAMEORIGIN")
                  end
    YAML
  public_gateway_blocked_paths_manifest    = <<-YAML
    apiVersion: security.istio.io/v1
    kind: AuthorizationPolicy
    metadata:
      name: public-gateway-blocked-paths
      namespace: ${local.istio_namespace}
    spec:
      selector:
        matchLabels:
          gateway.networking.k8s.io/gateway-name: public
      action: DENY
      rules:
        - to:
            - operation:
                ports:
                  - "80"
                  - "443"
                paths:
%{for path in var.public_gateway_blocked_paths~}
                  - ${jsonencode(path)}
%{endfor~}
    YAML
  public_gateway_local_rate_limit_manifest = <<-YAML
    apiVersion: networking.istio.io/v1alpha3
    kind: EnvoyFilter
    metadata:
      name: public-gateway-local-rate-limit
      namespace: ${local.istio_namespace}
    spec:
      workloadSelector:
        labels:
          gateway.networking.k8s.io/gateway-name: public
      configPatches:
        - applyTo: HTTP_FILTER
          match:
            context: GATEWAY
            listener:
              filterChain:
                filter:
                  name: envoy.filters.network.http_connection_manager
                  subFilter:
                    name: envoy.filters.http.router
          patch:
            operation: INSERT_BEFORE
            value:
              name: envoy.filters.http.local_ratelimit
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
                stat_prefix: public_gateway_local_rate_limiter
                token_bucket:
                  max_tokens: ${var.public_gateway_rate_limit_requests_per_minute}
                  tokens_per_fill: ${var.public_gateway_rate_limit_requests_per_minute}
                  fill_interval: 60s
                filter_enabled:
                  runtime_key: public_gateway_local_rate_limit_enabled
                  default_value:
                    numerator: 100
                    denominator: HUNDRED
                filter_enforced:
                  runtime_key: public_gateway_local_rate_limit_enforced
                  default_value:
                    numerator: 100
                    denominator: HUNDRED
                response_headers_to_add:
                  - append_action: OVERWRITE_IF_EXISTS_OR_ADD
                    header:
                      key: x-local-rate-limit
                      value: "true"
    YAML
  public_gateway_options                   = <<-YAML
    service: |
      spec:
        ipFamilyPolicy: SingleStack
        ipFamilies:
          - IPv4
        loadBalancerSourceRanges:
%{for cidr in var.public_gateway_allowed_cidrs~}
          - ${cidr}
%{endfor~}
    YAML
  central_egress_waypoint_manifest         = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: ${var.central_egress_waypoint_name}
      namespace: ${local.istio_namespace}
      labels:
        istio.io/waypoint-for: ${var.central_egress_waypoint_for}
    spec:
      gatewayClassName: istio-waypoint
      listeners:
        - name: mesh
          port: 15008
          protocol: HBONE
          allowedRoutes:
            namespaces:
              from: All
    YAML
  mesh_tracing_manifest                    = <<-YAML
    apiVersion: telemetry.istio.io/v1
    kind: Telemetry
    metadata:
      name: mesh-default
      namespace: ${local.istio_namespace}
    spec:
%{if var.enable_istio_access_logs~}
      accessLogging:
        - providers:
            - name: envoy
%{endif~}
%{if var.enable_istio_tracing~}
      tracing:
        - providers:
            - name: ${var.istio_tracing_provider_name}
          randomSamplingPercentage: ${var.istio_tracing_sampling_percentage}
%{endif~}
    YAML
  bookinfo_manifest                        = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: details
      namespace: default
      labels:
        app: details
        service: details
    spec:
      ports:
        - port: 9080
          name: http
      selector:
        app: details
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: ratings
      namespace: default
      labels:
        app: ratings
        service: ratings
    spec:
      ports:
        - port: 9080
          name: http
      selector:
        app: ratings
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: reviews
      namespace: default
      labels:
        app: reviews
        service: reviews
    spec:
      ports:
        - port: 9080
          name: http
      selector:
        app: reviews
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: productpage
      namespace: default
      labels:
        app: productpage
        service: productpage
    spec:
      ports:
        - port: 9080
          name: http
      selector:
        app: productpage
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: bookinfo-details
      namespace: default
      labels:
        account: details
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: details-v1
      namespace: default
      labels:
        app: details
        version: v1
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: details
          version: v1
      template:
        metadata:
          labels:
            app: details
            version: v1
        spec:
          serviceAccountName: bookinfo-details
          containers:
            - name: details
              image: docker.io/istio/examples-bookinfo-details-v1:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  memory: 128Mi
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: bookinfo-ratings
      namespace: default
      labels:
        account: ratings
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ratings-v1
      namespace: default
      labels:
        app: ratings
        version: v1
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: ratings
          version: v1
      template:
        metadata:
          labels:
            app: ratings
            version: v1
        spec:
          serviceAccountName: bookinfo-ratings
          containers:
            - name: ratings
              image: docker.io/istio/examples-bookinfo-ratings-v1:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  memory: 128Mi
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: bookinfo-reviews
      namespace: default
      labels:
        account: reviews
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: reviews-v1
      namespace: default
      labels:
        app: reviews
        version: v1
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: reviews
          version: v1
      template:
        metadata:
          labels:
            app: reviews
            version: v1
        spec:
          serviceAccountName: bookinfo-reviews
          containers:
            - name: reviews
              image: docker.io/istio/examples-bookinfo-reviews-v1:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 128Mi
                limits:
                  memory: 512Mi
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: reviews-v2
      namespace: default
      labels:
        app: reviews
        version: v2
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: reviews
          version: v2
      template:
        metadata:
          labels:
            app: reviews
            version: v2
        spec:
          serviceAccountName: bookinfo-reviews
          containers:
            - name: reviews
              image: docker.io/istio/examples-bookinfo-reviews-v2:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 64Mi
                limits:
                  memory: 256Mi
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: reviews-v3
      namespace: default
      labels:
        app: reviews
        version: v3
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: reviews
          version: v3
      template:
        metadata:
          labels:
            app: reviews
            version: v3
        spec:
          serviceAccountName: bookinfo-reviews
          containers:
            - name: reviews
              image: docker.io/istio/examples-bookinfo-reviews-v3:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 64Mi
                limits:
                  memory: 256Mi
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: bookinfo-productpage
      namespace: default
      labels:
        account: productpage
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: productpage-v1
      namespace: default
      labels:
        app: productpage
        version: v1
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: productpage
          version: v1
      template:
        metadata:
          labels:
            app: productpage
            version: v1
        spec:
          serviceAccountName: bookinfo-productpage
          containers:
            - name: productpage
              image: docker.io/istio/examples-bookinfo-productpage-v1:1.20.3
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 9080
              securityContext:
                runAsUser: 1000
              resources:
                requests:
                  cpu: 10m
                  memory: 128Mi
                limits:
                  memory: 512Mi
    YAML
  bookinfo_route_manifest                  = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: bookinfo
      namespace: default
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: lab
        platform.arcanjoconsultoria.com.br/auth: public
      annotations:
        external-dns.alpha.kubernetes.io/ttl: "60"
    spec:
      parentRefs:
        - name: public
          namespace: ${local.istio_namespace}
      hostnames:
%{for host in local.bookinfo_hosts~}
        - ${host}
%{endfor~}
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: productpage
              port: 9080
    YAML
  bookinfo_service_entry_manifest          = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: bookinfo-public-host
      namespace: ${local.istio_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
%{for host in local.bookinfo_hosts~}
        - ${host}
%{endfor~}
      location: MESH_EXTERNAL
      ports:
        - number: 80
          name: http
          protocol: HTTP
        - number: 443
          name: https
          protocol: HTTPS
      resolution: DNS
    YAML
}

resource "null_resource" "gateway_api_crds" {
  count = var.enabled && var.enable_gateway_api_crds ? 1 : 0

  triggers = {
    version = "v1.3.0"
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${self.triggers.version}/standard-install.yaml"
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  count = var.enabled && var.enable_cert_manager ? 1 : 0

  metadata {
    name = "cert-manager"
  }
}

resource "kubernetes_namespace_v1" "istio_system" {
  count = var.enabled && var.enable_istio_ambient ? 1 : 0

  metadata {
    name = local.istio_namespace
  }
}

resource "helm_release" "cert_manager" {
  count            = var.enabled && var.enable_cert_manager ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace_v1.cert_manager[0].metadata[0].name
  version          = "v1.20.2"
  create_namespace = false

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "20m"
          memory = "64Mi"
        }
        limits = {
          memory = "160Mi"
        }
      }
      cainjector = {
        resources = {
          requests = {
            cpu    = "20m"
            memory = "128Mi"
          }
          limits = {
            memory = "256Mi"
          }
        }
      }
      webhook = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "48Mi"
          }
          limits = {
            memory = "128Mi"
          }
        }
      }
    })
  ]
}

resource "helm_release" "cert_manager_oci_webhook" {
  count            = var.enabled && var.enable_cert_manager && var.enable_dns01_oci_webhook && (var.dns_provider == "oci" || var.preserve_legacy_oci_webhook) ? 1 : 0
  name             = "cert-manager-webhook-oci"
  chart            = "${path.module}/charts/cert-manager-webhook-oci"
  namespace        = kubernetes_namespace_v1.cert_manager[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      groupName = var.dns01_webhook_group_name
      image = {
        repository = var.dns01_oci_webhook_image_repository
        tag        = var.dns01_oci_webhook_image_tag
        pullPolicy = "IfNotPresent"
      }
      ociProfileSecretNames = []
      resources = {
        requests = {
          cpu    = "20m"
          memory = "64Mi"
        }
        limits = {
          memory = "128Mi"
        }
      }
    })
  ]

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "external_dns" {
  count      = var.enabled && var.enable_external_dns ? 1 : 0
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = var.external_dns_namespace
  version    = var.external_dns_chart_version

  values = [
    yamlencode(merge({
      provider = {
        name = var.dns_provider
      }
      policy           = var.external_dns_policy
      sources          = var.external_dns_sources
      gatewayNamespace = local.istio_namespace
      domainFilters = [
        var.domain_name
      ]
      extraArgs = concat(
        var.dns_provider == "oci" ? [
          "--oci-auth-instance-principal",
          "--oci-compartment-ocid=${var.compartment_ocid}",
          "--oci-zone-scope=GLOBAL"
        ] : [],
        var.dns_provider == "cloudflare" && var.external_dns_cloudflare_proxied ? ["--cloudflare-proxied"] : [],
        ["--gateway-name=public"],
        [for zone in var.external_dns_zone_id_filters : "--zone-id-filter=${zone}"],
        try(trimspace(var.external_dns_regex_domain_filter) != "", false) ? ["--regex-domain-filter=${var.external_dns_regex_domain_filter}"] : []
      )
      resources = {
        requests = {
          cpu    = "10m"
          memory = "64Mi"
        }
        limits = {
          memory = "128Mi"
        }
      }
      },
      var.external_dns_txt_owner_id != null ? { txtOwnerId = var.external_dns_txt_owner_id } : {},
      var.dns_provider == "cloudflare" ? {
        env = [{
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name = var.external_dns_cloudflare_api_token_secret_name
              key  = var.external_dns_cloudflare_api_token_secret_key
            }
          }
        }]
      } : {}
    ))
  ]

  lifecycle {
    precondition {
      condition = var.dns_provider != "cloudflare" || (
        try(trimspace(var.external_dns_cloudflare_api_token_secret_name) != "", false) &&
        length(var.external_dns_zone_id_filters) > 0 &&
        try(trimspace(var.external_dns_txt_owner_id) != "", false)
      )
      error_message = "Cloudflare ExternalDNS requires an existing token Secret name, explicit zone ID filters and a unique TXT owner ID."
    }
  }
}

resource "helm_release" "metrics_server" {
  count      = var.enabled && var.enable_metrics_server ? 1 : 0
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.13.0"

  values = [
    yamlencode({
      replicas = 1
      args = [
        "--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP",
        "--kubelet-use-node-status-port"
      ]
      resources = {
        requests = {
          cpu    = "50m"
          memory = "80Mi"
        }
        limits = {
          memory = "160Mi"
        }
      }
    })
  ]
}

resource "helm_release" "istio_base" {
  count            = var.enabled && var.enable_istio_ambient ? 1 : 0
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = kubernetes_namespace_v1.istio_system[0].metadata[0].name
  create_namespace = false
}

resource "helm_release" "istiod" {
  count      = var.enabled && var.enable_istio_ambient ? 1 : 0
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = kubernetes_namespace_v1.istio_system[0].metadata[0].name

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          memory = "768Mi"
        }
      }
      meshConfig = merge(
        var.enable_istio_access_logs ? {
          accessLogFile     = "/dev/stdout"
          accessLogEncoding = var.istio_access_log_encoding
          accessLogFormat = jsonencode({
            start_time                     = "%START_TIME%"
            method                         = "%REQ(:METHOD)%"
            path                           = "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
            protocol                       = "%PROTOCOL%"
            response_code                  = "%RESPONSE_CODE%"
            response_flags                 = "%RESPONSE_FLAGS%"
            response_code_details          = "%RESPONSE_CODE_DETAILS%"
            connection_termination_details = "%CONNECTION_TERMINATION_DETAILS%"
            bytes_received                 = "%BYTES_RECEIVED%"
            bytes_sent                     = "%BYTES_SENT%"
            duration_ms                    = "%DURATION%"
            upstream_service_time_ms       = "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%"
            x_forwarded_for                = "%REQ(X-FORWARDED-FOR)%"
            user_agent                     = "%REQ(USER-AGENT)%"
            request_id                     = "%REQ(X-REQUEST-ID)%"
            trace_id                       = "%REQ(X-B3-TRACEID)%"
            traceparent                    = "%REQ(TRACEPARENT)%"
            authority                      = "%REQ(:AUTHORITY)%"
            upstream_host                  = "%UPSTREAM_HOST%"
            upstream_cluster               = "%UPSTREAM_CLUSTER_RAW%"
            upstream_local_address         = "%UPSTREAM_LOCAL_ADDRESS%"
            downstream_local_address       = "%DOWNSTREAM_LOCAL_ADDRESS%"
            downstream_remote_address      = "%DOWNSTREAM_REMOTE_ADDRESS%"
            requested_server_name          = "%REQUESTED_SERVER_NAME%"
            route_name                     = "%ROUTE_NAME%"
            service_name                   = "%UPSTREAM_CLUSTER_RAW%"
          })
        } : {},
        var.enable_istio_tracing ? {
          extensionProviders = [
            {
              name = var.istio_tracing_provider_name
              opentelemetry = {
                service = var.istio_tracing_service
                port    = var.istio_tracing_port
              }
            }
          ]
        } : {}
      )
    })
  ]

  set = [
    {
      name  = "profile"
      value = "ambient"
    }
  ]

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_cni" {
  count      = var.enabled && var.enable_istio_ambient ? 1 : 0
  name       = "istio-cni"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "cni"
  namespace  = kubernetes_namespace_v1.istio_system[0].metadata[0].name

  set = [
    {
      name  = "profile"
      value = "ambient"
    }
  ]

  depends_on = [helm_release.istiod]
}

resource "helm_release" "ztunnel" {
  count      = var.enabled && var.enable_istio_ambient ? 1 : 0
  name       = "ztunnel"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "ztunnel"
  namespace  = kubernetes_namespace_v1.istio_system[0].metadata[0].name

  depends_on = [helm_release.istio_cni]
}

resource "kubernetes_config_map_v1" "public_gateway_options" {
  count = var.enabled && var.enable_public_ingress_gateway ? 1 : 0

  metadata {
    name      = "public-gateway-options"
    namespace = local.istio_namespace
  }

  data = yamldecode(local.public_gateway_options)

  depends_on = [kubernetes_namespace_v1.istio_system]
}

resource "null_resource" "letsencrypt_prod" {
  count = var.enabled && var.enable_wildcard_certificate ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.letsencrypt_prod_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.letsencrypt_prod_manifest}\nYAML"
  }

  lifecycle {
    precondition {
      condition     = var.dns_provider != "cloudflare" || try(trimspace(var.cloudflare_api_token_secret_name) != "", false)
      error_message = "Cloudflare DNS01 requires an existing token Secret name in cert-manager's cluster resource namespace."
    }
  }

  depends_on = [helm_release.cert_manager, helm_release.cert_manager_oci_webhook]
}

resource "null_resource" "wildcard_certificate" {
  count = var.enabled && var.enable_wildcard_certificate ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.wildcard_certificate_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.wildcard_certificate_manifest}\nYAML"
  }

  depends_on = [null_resource.letsencrypt_prod]
}

resource "null_resource" "wait_wildcard_certificate" {
  count = var.enabled && var.enable_wildcard_certificate ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.wildcard_certificate_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} -n ${local.istio_namespace} wait certificate/wildcard-${replace(var.domain_name, ".", "-")} --for=condition=Ready --timeout=20m"
  }

  depends_on = [null_resource.wildcard_certificate]
}

resource "null_resource" "public_gateway" {
  lifecycle {
    precondition {
      condition     = !contains(keys(var.additional_application_domains), var.domain_name) && length(setintersection(toset(values(var.public_gateway_listener_names)), toset(flatten([for alias in values(var.additional_application_domains) : compact([alias.http_listener_name, alias.https_listener_name])])))) == 0
      error_message = "Alias domains must differ from domain_name and all primary and alias listener names must be unique."
    }
  }

  count = var.enabled && var.enable_public_ingress_gateway ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.public_gateway_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_gateway_manifest}\nYAML"
  }

  depends_on = [
    null_resource.gateway_api_crds,
    helm_release.istiod,
    kubernetes_config_map_v1.public_gateway_options,
    null_resource.wait_wildcard_certificate
  ]
}

resource "null_resource" "public_gateway_fallback" {
  count = var.enabled && var.enable_public_ingress_gateway && var.enable_public_gateway_fallback ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.public_gateway_fallback_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_gateway_fallback_manifest}\nYAML"
  }

  depends_on = [null_resource.public_gateway]
}

resource "null_resource" "public_gateway_security_headers" {
  count = var.enabled && var.enable_public_ingress_gateway && var.enable_public_gateway_security_headers ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.public_gateway_security_headers_manifest)
    name            = "public-gateway-security-headers"
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_gateway_security_headers_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete envoyfilter ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.public_gateway]
}

resource "null_resource" "public_gateway_blocked_paths" {
  count = var.enabled && var.enable_public_ingress_gateway && var.enable_public_gateway_blocked_paths && length(var.public_gateway_blocked_paths) > 0 ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.public_gateway_blocked_paths_manifest)
    name            = "public-gateway-blocked-paths"
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_gateway_blocked_paths_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete authorizationpolicy ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.public_gateway]
}

resource "null_resource" "public_gateway_local_rate_limit" {
  count = var.enabled && var.enable_public_ingress_gateway && var.enable_public_gateway_local_rate_limit ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.public_gateway_local_rate_limit_manifest)
    name            = "public-gateway-local-rate-limit"
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_gateway_local_rate_limit_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete envoyfilter ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.public_gateway]
}

resource "null_resource" "central_egress_waypoint" {
  count = var.enabled && var.enable_istio_ambient && var.enable_central_egress_waypoint ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.central_egress_waypoint_manifest)
    name            = var.central_egress_waypoint_name
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.central_egress_waypoint_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete gateway ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [
    null_resource.gateway_api_crds,
    helm_release.istiod
  ]
}

resource "null_resource" "mesh_tracing" {
  count = var.enabled && var.enable_istio_ambient && (var.enable_istio_tracing || var.enable_istio_access_logs) ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.mesh_tracing_manifest)
    name            = "mesh-default"
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.mesh_tracing_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete telemetry ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [
    helm_release.istiod
  ]
}

resource "kubernetes_labels" "central_egress_waypoint_namespaces" {
  for_each = var.enabled && var.enable_istio_ambient && var.enable_central_egress_waypoint ? toset(var.central_egress_waypoint_namespaces) : toset([])

  api_version = "v1"
  kind        = "Namespace"
  force       = true

  metadata {
    name = each.value
  }

  labels = {
    "istio.io/dataplane-mode"         = "ambient"
    "istio.io/use-waypoint"           = var.central_egress_waypoint_name
    "istio.io/use-waypoint-namespace" = local.istio_namespace
  }

  depends_on = [null_resource.central_egress_waypoint]
}

resource "null_resource" "bookinfo_sample" {
  count = var.enabled && var.enable_bookinfo_sample ? 1 : 0

  triggers = {
    manifest_sha   = sha1(local.bookinfo_manifest)
    delete_command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete service productpage reviews ratings details -n default --ignore-not-found && ${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete deployment productpage-v1 reviews-v1 reviews-v2 reviews-v3 ratings-v1 details-v1 -n default --ignore-not-found && ${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete serviceaccount bookinfo-productpage bookinfo-reviews bookinfo-ratings bookinfo-details -n default --ignore-not-found"
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.bookinfo_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete service productpage reviews ratings details -n default --ignore-not-found && \"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete deployment productpage-v1 reviews-v1 reviews-v2 reviews-v3 ratings-v1 details-v1 -n default --ignore-not-found && \"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete serviceaccount bookinfo-productpage bookinfo-reviews bookinfo-ratings bookinfo-details -n default --ignore-not-found"
  }

  depends_on = [kubernetes_labels.central_egress_waypoint_namespaces]
}

resource "null_resource" "bookinfo_route" {
  count = var.enabled && var.enable_bookinfo_sample && var.enable_bookinfo_route ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.bookinfo_route_manifest)
    name            = "bookinfo"
    namespace       = "default"
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.bookinfo_route_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete httproute ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.public_gateway, null_resource.bookinfo_sample]
}

resource "null_resource" "bookinfo_public_host_service_entry" {
  count = var.enabled && var.enable_bookinfo_sample && var.enable_bookinfo_route ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.bookinfo_service_entry_manifest)
    name            = "bookinfo-public-host"
    namespace       = local.istio_namespace
    kubectl_path    = var.kubectl_path
    kubeconfig_path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.bookinfo_service_entry_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete serviceentry ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.bookinfo_route]
}
