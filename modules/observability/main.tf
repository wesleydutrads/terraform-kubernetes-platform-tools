locals {
  route_hosts = {
    kiali      = distinct(concat([var.hosts.kiali], lookup(var.additional_hosts, "kiali", [])))
    grafana    = distinct(concat([var.hosts.grafana], lookup(var.additional_hosts, "grafana", [])))
    tracing    = distinct(concat([var.hosts.tracing], lookup(var.additional_hosts, "tracing", [])))
    prometheus = distinct(compact(concat([try(var.hosts.prometheus, null)], lookup(var.additional_hosts, "prometheus", []))))
  }
  kubeconfig_path               = pathexpand(var.kubeconfig_path)
  tracing_host                  = var.hosts.tracing
  prometheus_host               = try(var.hosts.prometheus, null)
  tracing_backend               = var.enable_tempo ? "monitoring-grafana" : "jaeger"
  tracing_backend_port          = var.enable_tempo ? 80 : 16686
  oidc_issuer_host              = local.oidc_enabled ? regex("^https?://([^/]+)", var.oidc.issuer_url)[0] : null
  oauth2_proxy_issuer_host      = var.oauth2_proxy == null ? null : regex("^https?://([^/]+)", nonsensitive(var.oauth2_proxy.issuer_url))[0]
  monitoring_public_hosts       = distinct(compact(concat(local.route_hosts.kiali, local.route_hosts.grafana, local.route_hosts.tracing)))
  oauth_public_hosts            = var.enable_prometheus_route ? local.route_hosts.prometheus : []
  egress_public_hosts           = distinct(compact(concat(local.monitoring_public_hosts, [local.oidc_issuer_host], var.additional_egress_hosts)))
  oauth_egress_hosts            = distinct(compact(concat(local.oauth_public_hosts, [local.oauth2_proxy_issuer_host], var.additional_egress_hosts)))
  public_hosts_policy           = join("\n", [for host in local.monitoring_public_hosts : "                  - ${host}"])
  public_hosts_service_entry    = join("\n", [for host in local.egress_public_hosts : "        - ${host}"])
  oauth_hosts_service_entry     = join("\n", [for host in local.oauth_egress_hosts : "        - ${host}"])
  oidc_enabled                  = var.oidc != null
  loki_storage_endpoint_host    = var.loki_storage == null ? null : nonsensitive(replace(replace(var.loki_storage.endpoint, "https://", ""), "http://", ""))
  tempo_storage_endpoint_host   = var.tempo_storage == null ? null : nonsensitive(replace(replace(var.tempo_storage.endpoint, "https://", ""), "http://", ""))
  storage_endpoint_hosts        = distinct(compact([local.loki_storage_endpoint_host, local.tempo_storage_endpoint_host]))
  storage_service_entry_hosts   = join("\n", [for host in local.storage_endpoint_hosts : "        - ${host}"])
  kiali_discovery_override      = local.oidc_enabled ? try(var.oidc.kiali_discovery_override, null) : null
  kiali_dedicated_signing_key   = var.enabled && var.enable_kiali && var.kiali_dedicated_signing_key_enabled
  kiali_signing_key_secret_name = "kiali-signing-key"
  kiali_signing_key_secret_key  = "signing-key"
  # Default keeps the legacy value (var.monitoring_token); the dedicated mode uses the
  # Kiali chart's secret:<name>:<key> reference so the key never appears in Helm values.
  kiali_login_signing_key = local.kiali_dedicated_signing_key ? "secret:${local.kiali_signing_key_secret_name}:${local.kiali_signing_key_secret_key}" : var.monitoring_token
  kiali_discovery_override_values = local.kiali_discovery_override == null ? {} : {
    discovery_override = merge(
      try(local.kiali_discovery_override.authorization_endpoint, null) == null ? {} : {
        authorization_endpoint = local.kiali_discovery_override.authorization_endpoint
      },
      try(local.kiali_discovery_override.jwks_uri, null) == null ? {} : {
        jwks_uri = local.kiali_discovery_override.jwks_uri
      },
      try(local.kiali_discovery_override.token_endpoint, null) == null ? {} : {
        token_endpoint = local.kiali_discovery_override.token_endpoint
      },
      try(local.kiali_discovery_override.userinfo_endpoint, null) == null ? {} : {
        userinfo_endpoint = local.kiali_discovery_override.userinfo_endpoint
      }
    )
  }
  opentelemetry_collector_endpoint         = "http://${var.opentelemetry_collector_name}.${var.namespace}.svc.cluster.local:4318"
  opentelemetry_instrumentation_manifest   = <<-YAML
    apiVersion: opentelemetry.io/v1alpha1
    kind: Instrumentation
    metadata:
      name: ${var.opentelemetry_instrumentation_name}
      namespace: ${var.namespace}
    spec:
      exporter:
        endpoint: ${local.opentelemetry_collector_endpoint}
      propagators:
        - tracecontext
        - baggage
      sampler:
        type: parentbased_traceidratio
        argument: "1"
      resource:
        addK8sUIDAttributes: true
      env:
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: http/protobuf
        - name: OTEL_LOGS_EXPORTER
          value: otlp
        - name: OTEL_METRICS_EXPORTER
          value: otlp
        - name: OTEL_TRACES_EXPORTER
          value: otlp
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: deployment.environment.name=lab,k8s.cluster.name=oke-always-free
    YAML
  token_policy_manifest                    = <<-YAML
    apiVersion: security.istio.io/v1
    kind: AuthorizationPolicy
    metadata:
      name: monitoring-token-required
      namespace: ${var.gateway_namespace}
    spec:
      targetRefs:
        - group: gateway.networking.k8s.io
          kind: Gateway
          name: ${var.gateway_name}
      action: DENY
      rules:
        - to:
            - operation:
                hosts:
${local.public_hosts_policy}
          when:
            - key: request.headers[x-monitoring-token]
              notValues:
                - ${var.monitoring_token}
    YAML
  public_host_service_entry_manifest       = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: monitoring-public-hosts
      namespace: ${var.istio_root_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
${local.public_hosts_service_entry}
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
  storage_service_entry_manifest           = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: observability-object-storage
      namespace: ${var.istio_root_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
${local.storage_service_entry_hosts}
      location: MESH_EXTERNAL
      ports:
        - number: 443
          name: https
          protocol: TLS
      resolution: DNS
    YAML
  prometheus_route_manifest                = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: prometheus
      namespace: ${var.namespace}
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: administrative
        platform.arcanjoconsultoria.com.br/auth: oauth2-proxy
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.route_hosts.prometheus~}
        - ${host}
%{endfor~}
      rules:
        - backendRefs:
            - name: prometheus-oauth2-proxy
              port: 80
    YAML
  oauth_public_host_service_entry_manifest = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: oauth-protected-public-hosts
      namespace: ${var.istio_root_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
${local.oauth_hosts_service_entry}
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
  istio_pod_monitors_manifest              = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: istio-ztunnel-metrics
      namespace: ${var.istio_root_namespace}
      labels:
        release: monitoring
        istio-metrics: ztunnel
    spec:
      selector:
        app: ztunnel
      ports:
        - name: ztunnel-stats
          port: 15020
          targetPort: 15020
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: public-istio-metrics
      namespace: ${var.istio_root_namespace}
      labels:
        release: monitoring
        istio-metrics: gateway
    spec:
      selector:
        gateway.networking.k8s.io/gateway-name: ${var.gateway_name}
      ports:
        - name: http-envoy-prom
          port: 15090
          targetPort: 15090
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: egress-waypoint-metrics
      namespace: ${var.istio_root_namespace}
      labels:
        release: monitoring
        istio-metrics: gateway
    spec:
      selector:
        gateway.networking.k8s.io/gateway-name: egress-waypoint
      ports:
        - name: http-envoy-prom
          port: 15090
          targetPort: 15090
    ---
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: istio-ztunnel
      namespace: ${var.namespace}
      labels:
        release: monitoring
    spec:
      namespaceSelector:
        matchNames:
          - ${var.istio_root_namespace}
      selector:
        matchLabels:
          istio-metrics: ztunnel
      endpoints:
        - port: ztunnel-stats
          path: /stats/prometheus
          interval: 15s
    ---
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: istio-gateways
      namespace: ${var.namespace}
      labels:
        release: monitoring
    spec:
      namespaceSelector:
        matchNames:
          - ${var.istio_root_namespace}
      selector:
        matchLabels:
          istio-metrics: gateway
      endpoints:
        - port: http-envoy-prom
          path: /stats/prometheus
          interval: 15s
    ---
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: istiod
      namespace: ${var.namespace}
      labels:
        release: monitoring
    spec:
      namespaceSelector:
        matchNames:
          - ${var.istio_root_namespace}
      selector:
        matchLabels:
          app: istiod
      endpoints:
        - port: http-monitoring
          path: /metrics
          interval: 15s
    YAML
  kiali_route_manifest                     = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: kiali
      namespace: ${var.namespace}
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: administrative
        platform.arcanjoconsultoria.com.br/auth: oidc
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.route_hosts.kiali~}
        - ${host}
%{endfor~}
      rules:
        - filters:
            - type: RequestHeaderModifier
              requestHeaderModifier:
                set:
                  - name: X-Forwarded-Port
                    value: "443"
                  - name: X-Forwarded-Proto
                    value: https
          backendRefs:
            - name: kiali
              port: 20001
    YAML
  grafana_route_manifest                   = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: grafana
      namespace: ${var.namespace}
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: administrative
        platform.arcanjoconsultoria.com.br/auth: oidc
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.route_hosts.grafana~}
        - ${host}
%{endfor~}
      rules:
        - backendRefs:
            - name: monitoring-grafana
              port: 80
    YAML
  tracing_route_manifest                   = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: tracing
      namespace: ${var.namespace}
      labels:
        platform.arcanjoconsultoria.com.br/exposure-class: administrative
        platform.arcanjoconsultoria.com.br/auth: oidc
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.route_hosts.tracing~}
        - ${host}
%{endfor~}
      rules:
        - backendRefs:
            - name: ${local.tracing_backend}
              port: ${local.tracing_backend_port}
    YAML
}

resource "kubernetes_namespace_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels]
  }
}

resource "kubernetes_secret_v1" "grafana_oidc" {
  count = var.enabled && var.enable_prometheus_stack && local.oidc_enabled ? 1 : 0

  metadata {
    name      = "grafana-oidc"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  data = {
    client-secret = var.oidc.grafana_client_secret
  }
}

resource "helm_release" "prometheus_stack" {
  version          = var.prometheus_stack_chart_version
  count            = var.enabled && var.enable_prometheus_stack ? 1 : 0
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      grafana = {
        enabled       = true
        adminPassword = var.monitoring_token
        resources = {
          requests = {
            cpu    = "50m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "768Mi"
          }
        }
        sidecar = {
          dashboards = {
            resources = {
              requests = {
                cpu    = "10m"
                memory = "96Mi"
              }
              limits = {
                memory = "160Mi"
              }
            }
          }
          datasources = {
            resources = {
              requests = {
                cpu    = "10m"
                memory = "96Mi"
              }
              limits = {
                memory = "160Mi"
              }
            }
          }
        }
        "grafana.ini" = merge({
          server = {
            domain   = var.hosts.grafana
            protocol = "http"
            root_url = "https://${var.hosts.grafana}"
          }
          "auth.anonymous" = {
            enabled  = var.enable_grafana_anonymous_viewer
            org_name = "Main Org."
            org_role = "Viewer"
          }
          users = {
            viewers_can_edit = false
          }
          }, local.oidc_enabled ? {
          "auth.generic_oauth" = {
            enabled             = true
            name                = "Keycloak"
            allow_sign_up       = true
            client_id           = var.oidc.grafana_client_id
            client_secret       = "$__env{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}"
            scopes              = "openid profile email"
            auth_url            = coalesce(try(var.oidc.grafana_auth_url, null), "${var.oidc.issuer_url}/protocol/openid-connect/auth")
            token_url           = coalesce(try(var.oidc.grafana_token_url, null), "${var.oidc.issuer_url}/protocol/openid-connect/token")
            api_url             = coalesce(try(var.oidc.grafana_api_url, null), "${var.oidc.issuer_url}/protocol/openid-connect/userinfo")
            role_attribute_path = "contains(groups[*], '${var.oidc.admin_group}') && 'Admin' || contains(groups[*], '${var.oidc.readonly_group}') && 'Viewer' || 'Viewer'"
          }
        } : {})
        envValueFrom = local.oidc_enabled ? {
          GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = {
            secretKeyRef = {
              name = kubernetes_secret_v1.grafana_oidc[0].metadata[0].name
              key  = "client-secret"
            }
          }
        } : {}
        plugins = var.enable_profiles_drilldown ? ["grafana-pyroscope-app"] : []
        persistence = {
          enabled          = var.enable_grafana_persistence
          storageClassName = var.monitoring_storage_class_name
          size             = var.grafana_storage_size
        }
        additionalDataSources = concat(
          var.enable_loki ? [
            {
              name      = "Loki"
              uid       = "loki"
              type      = "loki"
              access    = "proxy"
              url       = "http://loki-gateway.${var.namespace}.svc.cluster.local"
              isDefault = false
            }
          ] : [],
          var.enable_tempo ? [
            {
              name   = "Tempo"
              uid    = "tempo"
              type   = "tempo"
              access = "proxy"
              url    = "http://tempo.${var.namespace}.svc.cluster.local:3200"
              jsonData = {
                tracesToLogsV2 = {
                  datasourceUid      = "loki"
                  spanStartTimeShift = "-1h"
                  spanEndTimeShift   = "1h"
                  tags = [
                    { key = "service.name", value = "service_name" },
                  ]
                  filterByTraceID = true
                  filterBySpanID  = false
                }
                tracesToProfiles = var.enable_profiles_drilldown && var.pyroscope_datasource_url != null ? {
                  datasourceUid = "pyroscope"
                  tags = [
                    { key = "service.name", value = "service_name" },
                    { key = "k8s.namespace.name", value = "namespace" },
                  ]
                  profileTypeId = "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
                  customQuery   = true
                  query         = "{$$__tags}"
                } : null
                tracesToMetrics = {
                  datasourceUid      = "prometheus"
                  spanStartTimeShift = "-1h"
                  spanEndTimeShift   = "1h"
                  tags = [
                    { key = "service.name", value = "service" },
                  ]
                  queries = [
                    {
                      name  = "Span calls"
                      query = "sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))"
                    },
                    {
                      name  = "Span latency p95"
                      query = "histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket{$$__tags}[5m])) by (le))"
                    }
                  ]
                }
                serviceMap = {
                  datasourceUid = "prometheus"
                }
                nodeGraph = {
                  enabled = true
                }
                search = {
                  hide = false
                }
                traceQuery = {
                  timeShiftEnabled   = true
                  spanStartTimeShift = "-1h"
                  spanEndTimeShift   = "1h"
                }
              }
            }
          ] : [],
          var.enable_profiles_drilldown && var.pyroscope_datasource_url != null ? [
            {
              name   = "Pyroscope"
              uid    = "pyroscope"
              type   = "grafana-pyroscope-datasource"
              access = "proxy"
              url    = var.pyroscope_datasource_url
            }
          ] : []
        )
      }
      alertmanager = {
        enabled = false
      }
      prometheus = {
        prometheusSpec = {
          retention                 = "12h"
          enableRemoteWriteReceiver = var.enable_tempo && var.enable_tempo_metrics_generator
          resources = {
            requests = {
              cpu    = "100m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "750m"
              memory = "2Gi"
            }
          }
          podMetadata = {
            labels = {
              "istio.io/dataplane-mode" = "none"
            }
          }
          storageSpec = var.enable_prometheus_persistence ? {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.monitoring_storage_class_name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          } : null
        }
      }
      prometheusOperator = {
        resources = {
          requests = {
            cpu    = "20m"
            memory = "64Mi"
          }
          limits = {
            memory = "192Mi"
          }
        }
        prometheusConfigReloader = {
          resources = {
            requests = {
              cpu    = "5m"
              memory = "32Mi"
            }
            limits = {
              memory = "96Mi"
            }
          }
        }
      }
      "kube-state-metrics" = {
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
      "prometheus-node-exporter" = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "32Mi"
          }
          limits = {
            memory = "96Mi"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_secret_v1.grafana_oidc]
}

resource "helm_release" "loki" {
  count            = var.enabled && var.enable_loki ? 1 : 0
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"
      loki = {
        auth_enabled = false
        commonConfig = {
          path_prefix        = "/tmp/loki"
          replication_factor = 1
        }
        pattern_ingester = {
          enabled = var.enable_loki_pattern_ingester
        }
        storage = {
          type = "s3"
          bucketNames = {
            chunks = var.loki_storage.bucket_name
            ruler  = var.loki_storage.bucket_name
            admin  = var.loki_storage.bucket_name
          }
          s3 = {
            endpoint          = var.loki_storage.endpoint
            region            = var.loki_storage.region
            accessKeyId       = var.loki_storage.access_key_id
            secretAccessKey   = var.loki_storage.secret_access_key
            s3ForcePathStyle  = true
            signatureVersion  = "v4"
            insecure          = false
            disable_dualstack = true
          }
        }
        schemaConfig = {
          configs = [
            {
              from         = "2024-04-01"
              store        = "tsdb"
              object_store = "s3"
              schema       = "v13"
              index = {
                prefix = "loki_index_"
                period = "24h"
              }
            }
          ]
        }
        limits_config = {
          retention_period          = var.loki_retention_period
          ingestion_rate_mb         = var.loki_ingestion_rate_mb
          ingestion_burst_size_mb   = var.loki_ingestion_burst_size_mb
          allow_structured_metadata = true
        }
        compactor = {
          working_directory    = "/tmp/loki/compactor"
          retention_enabled    = true
          delete_request_store = "s3"
        }
        rulerConfig = {
          wal = {
            dir = "/tmp/loki/ruler-wal"
          }
        }
        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/tmp/loki/tsdb-index"
            cache_location         = "/tmp/loki/tsdb-cache"
          }
          bloom_shipper = {
            working_directory = "/tmp/loki/bloomshipper"
          }
        }
      }
      singleBinary = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "50m"
            memory = "768Mi"
          }
          limits = {
            memory = "1536Mi"
          }
        }
        persistence = {
          enabled = false
        }
      }
      gateway = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "32Mi"
          }
          limits = {
            memory = "128Mi"
          }
        }
      }
      sidecar = {
        rules = {
          resources = {
            requests = {
              cpu    = "5m"
              memory = "96Mi"
            }
            limits = {
              memory = "160Mi"
            }
          }
        }
      }
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }
      chunksCache = {
        enabled = false
      }
      resultsCache = {
        enabled = false
      }
      test = {
        enabled = false
      }
      lokiCanary = {
        enabled = false
      }
    })
  ]
}

resource "helm_release" "prometheus_oauth2_proxy" {
  count            = var.enabled && var.enable_prometheus_stack && var.enable_prometheus_route && var.oauth2_proxy != null ? 1 : 0
  name             = "prometheus-oauth2-proxy"
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = var.oauth2_proxy_chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      config = {
        clientID     = nonsensitive(var.oauth2_proxy.client_id)
        clientSecret = var.oauth2_proxy.client_secret
        cookieSecret = var.oauth2_proxy.cookie_secret
        emailDomains = ["*"]
      }
      extraArgs = {
        provider               = "oidc"
        "oidc-issuer-url"      = nonsensitive(var.oauth2_proxy.issuer_url)
        "skip-oidc-discovery"  = "true"
        "login-url"            = "${nonsensitive(var.oauth2_proxy.issuer_url)}/protocol/openid-connect/auth"
        "redeem-url"           = "http://keycloak.keycloak.svc.cluster.local:8080/realms/platform/protocol/openid-connect/token"
        "profile-url"          = "http://keycloak.keycloak.svc.cluster.local:8080/realms/platform/protocol/openid-connect/userinfo"
        "oidc-jwks-url"        = "http://keycloak.keycloak.svc.cluster.local:8080/realms/platform/protocol/openid-connect/certs"
        "redirect-url"         = "https://${local.prometheus_host}/oauth2/callback"
        upstream               = "http://monitoring-kube-prometheus-prometheus.${var.namespace}.svc.cluster.local:9090"
        "reverse-proxy"        = "true"
        "set-xauthrequest"     = "true"
        "pass-user-headers"    = "true"
        "pass-access-token"    = "true"
        "skip-provider-button" = "true"
        "trusted-proxy-ip"     = "10.0.0.0/8,169.254.0.0/16"
        "cookie-secure"        = "true"
        "cookie-samesite"      = "lax"
        "cookie-expire"        = "8h"
        scope                  = "openid profile email"
        "allowed-group"        = "platform-admins"
      }
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
      redis-ha = {
        enabled = false
      }
      initContainers = {
        waitForRedis = {
          enabled = false
        }
      }
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
          labels = {
            release = "monitoring"
          }
        }
      }
    })
  ]

  depends_on = [helm_release.prometheus_stack]
}

resource "helm_release" "promtail" {
  count            = var.enabled && var.enable_loki && var.enable_promtail ? 1 : 0
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://loki-gateway.${var.namespace}.svc.cluster.local/loki/api/v1/push"
            external_labels = {
              cluster     = "oke-always-free"
              environment = "lab"
            }
          }
        ]
        snippets = {
          extraRelabelConfigs = [
            {
              action        = "replace"
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "service_namespace"
            },
            {
              action = "replace"
              source_labels = [
                "__meta_kubernetes_pod_label_app_kubernetes_io_name",
                "__meta_kubernetes_pod_label_app",
                "__tmp_controller_name",
                "__meta_kubernetes_pod_name"
              ]
              regex        = "^;*([^;]+)(;.*)?$"
              target_label = "service_name"
            },
            {
              action        = "replace"
              source_labels = ["__tmp_controller_name"]
              target_label  = "workload"
            },
            {
              action = "replace"
              source_labels = [
                "__meta_kubernetes_pod_label_app_kubernetes_io_part_of",
                "__meta_kubernetes_pod_label_app_kubernetes_io_instance"
              ]
              regex        = "^;*([^;]+)(;.*)?$"
              target_label = "part_of"
            }
          ]
          pipelineStages = [
            {
              cri = {}
            },
            {
              match = {
                selector      = "{container=\"istio-proxy\"}"
                pipeline_name = "istio_envoy_access_logs"
                stages = [
                  {
                    json = {
                      expressions = {
                        authority        = "authority"
                        duration_ms      = "duration_ms"
                        method           = "method"
                        path             = "path"
                        request_id       = "request_id"
                        response_code    = "response_code"
                        route_name       = "route_name"
                        trace_id         = "trace_id"
                        traceparent      = "traceparent"
                        upstream_cluster = "upstream_cluster"
                        upstream_host    = "upstream_host"
                        user_agent       = "user_agent"
                        x_forwarded_for  = "x_forwarded_for"
                      }
                    }
                  },
                  {
                    regex = {
                      expression = "^(?:(?:outbound|inbound-vip)\\|[^|]*\\|[^|]*\\|)?(?P<service_name>[^|]+\\.svc\\.cluster\\.local).*$"
                      source     = "upstream_cluster"
                    }
                  },
                  {
                    regex = {
                      expression = "^00-(?P<trace_id>[0-9a-f]{32})-(?P<span_id>[0-9a-f]{16})-[0-9a-f]{2}$"
                      source     = "traceparent"
                    }
                  },
                  {
                    labels = {
                      authority     = ""
                      method        = ""
                      response_code = ""
                      service_name  = ""
                    }
                  },
                  {
                    structured_metadata = {
                      duration_ms      = ""
                      path             = ""
                      request_id       = ""
                      route_name       = ""
                      span_id          = ""
                      trace_id         = ""
                      traceparent      = ""
                      upstream_cluster = ""
                      upstream_host    = ""
                      user_agent       = ""
                      x_forwarded_for  = ""
                    }
                  }
                ]
              }
            }
          ]
        }
      }
      resources = {
        requests = {
          cpu    = "20m"
          memory = "64Mi"
        }
        limits = {
          memory = "160Mi"
        }
      }
    })
  ]

  depends_on = [helm_release.loki]
}

resource "helm_release" "tempo" {
  count            = var.enabled && var.enable_tempo ? 1 : 0
  name             = "tempo"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      replicas = 1
      tempo = {
        retention = var.tempo_retention_period
        resources = {
          requests = {
            cpu    = "100m"
            memory = "2Gi"
          }
          limits = {
            memory = "4Gi"
          }
        }
        metricsGenerator = {
          enabled = var.enable_tempo_metrics_generator
          processor = var.enable_tempo_metrics_generator ? {
            local_blocks = {
              filter_server_spans = false
              flush_to_storage    = true
            }
            service_graphs = {}
            span_metrics   = {}
          } : {}
          storage = {
            path = "/tmp/tempo"
            remote_write = var.enable_tempo_metrics_generator ? [
              {
                url = "http://monitoring-kube-prometheus-prometheus.${var.namespace}.svc.cluster.local:9090/api/v1/write"
              }
            ] : []
          }
        }
        overrides = {
          defaults = var.enable_tempo_metrics_generator ? {
            metrics_generator = {
              processors = ["service-graphs", "span-metrics", "local-blocks"]
            }
          } : {}
          per_tenant_override_config = "/conf/overrides.yaml"
        }
        storage = {
          trace = {
            backend = "s3"
            wal = {
              path = "/tmp/tempo/wal"
            }
            s3 = {
              bucket         = var.tempo_storage.bucket_name
              endpoint       = replace(var.tempo_storage.endpoint, "https://", "")
              region         = var.tempo_storage.region
              access_key     = var.tempo_storage.access_key_id
              secret_key     = var.tempo_storage.secret_access_key
              forcepathstyle = true
              insecure       = false
            }
          }
        }
      }
      persistence = {
        enabled = false
      }
      tempoQuery = {
        enabled = false
      }
      serviceMonitor = {
        enabled = false
      }
    })
  ]
}

resource "helm_release" "opentelemetry_operator" {
  count            = var.enabled && var.enable_opentelemetry_operator ? 1 : 0
  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  version          = var.opentelemetry_operator_chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      manager = {
        resources = {
          requests = {
            cpu    = "20m"
            memory = "64Mi"
          }
          limits = {
            memory = "256Mi"
          }
        }
        serviceMonitor = {
          enabled = var.enable_prometheus_stack
          extraLabels = {
            release = "monitoring"
          }
        }
      }
      admissionWebhooks = {
        certManager = {
          enabled = true
        }
      }
    })
  ]
}

resource "kubernetes_cluster_role_binding_v1" "opentelemetry_operator_auth_delegator" {
  count = var.enabled && var.enable_opentelemetry_operator && var.enable_prometheus_stack ? 1 : 0

  metadata {
    name = "${var.namespace}-opentelemetry-operator-auth-delegator"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "opentelemetry-operator"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  depends_on = [helm_release.opentelemetry_operator]
}

resource "helm_release" "opentelemetry_collector_gateway" {
  count            = var.enabled && var.enable_opentelemetry_collector_gateway ? 1 : 0
  name             = var.opentelemetry_collector_name
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.opentelemetry_collector_chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      fullnameOverride = var.opentelemetry_collector_name
      mode             = "deployment"
      replicaCount     = 1
      image = {
        repository = "docker.io/otel/opentelemetry-collector-contrib"
      }
      presets = {
        kubernetesAttributes = {
          enabled = false
        }
      }
      clusterRole = {
        create = true
        rules = [
          {
            apiGroups = [""]
            resources = ["pods", "namespaces", "nodes"]
            verbs     = ["get", "list", "watch"]
          },
          {
            apiGroups = ["apps"]
            resources = ["replicasets"]
            verbs     = ["get", "list", "watch"]
          }
        ]
      }
      ports = {
        otlp = {
          enabled       = true
          containerPort = 4317
          servicePort   = 4317
          protocol      = "TCP"
          appProtocol   = "grpc"
        }
        "otlp-http" = {
          enabled       = true
          containerPort = 4318
          servicePort   = 4318
          protocol      = "TCP"
        }
        metrics = {
          enabled       = true
          containerPort = 8888
          servicePort   = 8888
          protocol      = "TCP"
        }
        "app-metrics" = {
          enabled       = true
          containerPort = 8889
          servicePort   = 8889
          protocol      = "TCP"
        }
        "jaeger-compact" = {
          enabled = false
        }
        "jaeger-thrift" = {
          enabled = false
        }
        "jaeger-grpc" = {
          enabled = false
        }
        zipkin = {
          enabled = false
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "192Mi"
        }
        limits = {
          memory = "512Mi"
        }
      }
      serviceMonitor = {
        enabled = var.enable_prometheus_stack
        metricsEndpoints = [
          {
            port = "metrics"
          },
          {
            port = "app-metrics"
          }
        ]
        extraLabels = {
          release = "monitoring"
        }
      }
      alternateConfig = {
        extensions = {
          health_check = {
            endpoint = "0.0.0.0:13133"
          }
        }
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
        }
        processors = {
          memory_limiter = {
            check_interval         = "5s"
            limit_percentage       = 80
            spike_limit_percentage = 25
          }
          k8s_attributes = {
            auth_type = "serviceAccount"
            extract = {
              metadata = [
                "k8s.namespace.name",
                "k8s.pod.name",
                "k8s.pod.uid",
                "k8s.deployment.name",
                "k8s.node.name",
                "k8s.container.name",
                "container.image.name",
                "container.image.tag"
              ]
              labels = [
                {
                  tag_name = "service_name"
                  key      = "app.kubernetes.io/name"
                  from     = "pod"
                },
                {
                  tag_name = "service_namespace"
                  key      = "app.kubernetes.io/part-of"
                  from     = "pod"
                },
                {
                  tag_name = "service_version"
                  key      = "app.kubernetes.io/version"
                  from     = "pod"
                }
              ]
            }
            pod_association = [
              {
                sources = [
                  {
                    from = "resource_attribute"
                    name = "k8s.pod.ip"
                  }
                ]
              },
              {
                sources = [
                  {
                    from = "resource_attribute"
                    name = "k8s.pod.uid"
                  }
                ]
              },
              {
                sources = [
                  {
                    from = "connection"
                  }
                ]
              }
            ]
          }
          resource = {
            attributes = [
              {
                key    = "k8s.cluster.name"
                value  = "oke-always-free"
                action = "upsert"
              },
              {
                key    = "deployment.environment.name"
                value  = "lab"
                action = "upsert"
              }
            ]
          }
          batch = {}
        }
        exporters = merge(
          var.enable_tempo ? {
            "otlp_http/tempo" = {
              endpoint = "http://tempo.${var.namespace}.svc.cluster.local:4318"
              tls = {
                insecure = true
              }
            }
          } : {},
          var.enable_prometheus_stack ? {
            prometheus = {
              endpoint = "0.0.0.0:8889"
              resource_to_telemetry_conversion = {
                enabled = true
              }
            }
          } : {},
          var.enable_loki ? {
            "otlp_http/loki" = {
              endpoint = "http://loki-gateway.${var.namespace}.svc.cluster.local/otlp"
              tls = {
                insecure = true
              }
            }
          } : {}
        )
        service = {
          extensions = ["health_check"]
          pipelines = merge(
            var.enable_tempo ? {
              traces = {
                receivers  = ["otlp"]
                processors = ["memory_limiter", "k8s_attributes", "resource", "batch"]
                exporters  = ["otlp_http/tempo"]
              }
            } : {},
            var.enable_prometheus_stack ? {
              metrics = {
                receivers  = ["otlp"]
                processors = ["memory_limiter", "resource", "batch"]
                exporters  = ["prometheus"]
              }
            } : {},
            var.enable_loki ? {
              logs = {
                receivers  = ["otlp"]
                processors = ["memory_limiter", "k8s_attributes", "resource", "batch"]
                exporters  = ["otlp_http/loki"]
              }
            } : {}
          )
          telemetry = {
            metrics = {
              readers = [
                {
                  pull = {
                    exporter = {
                      prometheus = {
                        host = "0.0.0.0"
                        port = 8888
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.tempo, helm_release.loki, helm_release.prometheus_stack]
}

resource "null_resource" "opentelemetry_instrumentation" {
  count = var.enabled && var.enable_opentelemetry_operator && var.enable_opentelemetry_collector_gateway && var.enable_opentelemetry_instrumentation ? 1 : 0

  triggers = {
    manifest_sha         = sha1(local.opentelemetry_instrumentation_manifest)
    instrumentation_name = var.opentelemetry_instrumentation_name
    instrumentation_ns   = var.namespace
    kubeconfig_path      = local.kubeconfig_path
    kubectl_path         = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.opentelemetry_instrumentation_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete instrumentation ${self.triggers.instrumentation_name} -n ${self.triggers.instrumentation_ns} --ignore-not-found"
  }

  depends_on = [helm_release.opentelemetry_operator, helm_release.opentelemetry_collector_gateway]
}

resource "helm_release" "jaeger" {
  count            = var.enabled && var.enable_jaeger ? 1 : 0
  name             = "jaeger"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      provisionDataStore = {
        cassandra = false
      }
      allInOne = {
        enabled = true
      }
      jaeger = {
        image = {
          registry = "docker.io"
        }
      }
      storage = {
        type = "memory"
      }
      agent = {
        enabled = false
      }
      collector = {
        enabled = false
      }
      query = {
        enabled = false
      }
    })
  ]
}

resource "helm_release" "kiali" {
  version          = var.kiali_chart_version
  count            = var.enabled && var.enable_kiali ? 1 : 0
  name             = "kiali"
  repository       = "https://kiali.org/helm-charts"
  chart            = "kiali-server"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      deployment = merge({
        resources = {
          requests = {
            cpu    = "25m"
            memory = "128Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
        }, local.kiali_dedicated_signing_key ? {
        # Roll the Kiali pod when the signing key is rotated so it remounts the new Secret.
        pod_annotations = {
          "kiali.io/signing-key-rotation" = var.kiali_signing_key_rotation
        }
      } : {})
      auth = merge({
        strategy = var.kiali_auth_strategy
        }, local.oidc_enabled && var.kiali_auth_strategy == "openid" ? {
        openid = merge({
          client_id      = var.oidc.kiali_client_id
          issuer_uri     = var.oidc.issuer_url
          scopes         = ["openid", "profile", "email"]
          username_claim = "preferred_username"
          disable_rbac   = true
        }, local.kiali_discovery_override_values)
      } : {})
      login_token = {
        expiration_seconds = var.kiali_login_token_expiration_seconds
        signing_key        = local.kiali_login_signing_key
      }
      external_services = {
        prometheus = {
          url = "http://monitoring-kube-prometheus-prometheus.${var.namespace}.svc:9090"
        }
        istio = {
          root_namespace = var.istio_root_namespace
        }
        grafana = {
          enabled        = var.enable_prometheus_stack
          internal_url   = "http://monitoring-grafana.${var.namespace}.svc"
          external_url   = "https://${var.hosts.grafana}"
          datasource_uid = "prometheus"
        }
        tracing = {
          enabled          = var.enable_tempo || var.enable_jaeger
          internal_url     = var.enable_tempo ? "http://tempo.${var.namespace}.svc.cluster.local:3200" : "http://jaeger.${var.namespace}.svc:16686"
          health_check_url = var.enable_tempo ? "http://tempo.${var.namespace}.svc.cluster.local:3200/ready" : "http://jaeger.${var.namespace}.svc:16686"
          external_url     = var.enable_tempo ? "https://${var.hosts.grafana}" : "https://${local.tracing_host}"
          provider         = var.enable_tempo ? "tempo" : "jaeger"
          use_grpc         = false
          tempo_config = var.enable_tempo ? {
            datasource_uid = "tempo"
            org_id         = "1"
            url_format     = "grafana"
          } : null
        }
      }
    })
  ]

  depends_on = [kubernetes_secret_v1.kiali_oidc, kubernetes_secret_v1.kiali_signing_key]
}

# Dedicated Kiali login token signing key, independent from var.monitoring_token.
# Rotate by changing var.kiali_signing_key_rotation (random_password keeper).
resource "random_password" "kiali_signing_key" {
  count = local.kiali_dedicated_signing_key ? 1 : 0

  length  = 32
  special = false

  keepers = {
    rotation = var.kiali_signing_key_rotation
  }
}

resource "kubernetes_secret_v1" "kiali_signing_key" {
  count = local.kiali_dedicated_signing_key ? 1 : 0

  metadata {
    name      = local.kiali_signing_key_secret_name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    labels = {
      app = "kiali"
    }
  }

  data = {
    (local.kiali_signing_key_secret_key) = random_password.kiali_signing_key[0].result
  }
}

resource "kubernetes_secret_v1" "kiali_oidc" {
  count = var.enabled && var.enable_kiali && local.oidc_enabled && var.kiali_auth_strategy == "openid" ? 1 : 0

  metadata {
    name      = "kiali"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    labels = {
      app = "kiali"
    }
  }

  data = {
    oidc-secret = var.oidc.kiali_client_secret
  }
}

resource "kubernetes_service_account_v1" "kiali_admin" {
  count = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? 1 : 0

  metadata {
    name      = var.kiali_admin_service_account_name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding_v1" "kiali_admin" {
  count = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? 1 : 0

  metadata {
    name = "${var.namespace}-${var.kiali_admin_service_account_name}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.kiali_admin[0].metadata[0].name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
}

resource "kubernetes_service_account_v1" "kiali_readonly" {
  count = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? 1 : 0

  metadata {
    name      = var.kiali_readonly_service_account_name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  depends_on = [helm_release.kiali]
}

resource "kubernetes_cluster_role_binding_v1" "kiali_readonly" {
  count = var.enabled && var.enable_kiali && var.enable_monitoring_access_rbac ? 1 : 0

  metadata {
    name = "${var.namespace}-${var.kiali_readonly_service_account_name}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kiali-viewer"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.kiali_readonly[0].metadata[0].name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  depends_on = [helm_release.kiali]
}

resource "null_resource" "token_policy" {
  count = var.enabled ? 1 : 0

  triggers = {
    enabled      = tostring(var.enable_monitoring_token_policy)
    manifest_sha = nonsensitive(sha1(local.token_policy_manifest))
  }

  provisioner "local-exec" {
    command = var.enable_monitoring_token_policy ? "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.token_policy_manifest}\nYAML" : "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete authorizationpolicy monitoring-token-required -n ${var.gateway_namespace} --ignore-not-found"
  }

  depends_on = [helm_release.kiali]
}

resource "null_resource" "public_host_service_entries" {
  count = var.enabled && var.enable_public_host_service_entries ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.public_host_service_entry_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.public_host_service_entry_manifest}\nYAML"
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "null_resource" "oauth_public_host_service_entries" {
  count = var.enabled && var.enable_public_host_service_entries && length(local.oauth_egress_hosts) > 0 ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.oauth_public_host_service_entry_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.oauth_public_host_service_entry_manifest}\nYAML"
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "null_resource" "storage_service_entries" {
  count = var.enabled && length(local.storage_endpoint_hosts) > 0 ? 1 : 0

  triggers = {
    manifest_sha = sha1(nonsensitive(local.storage_service_entry_manifest))
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${nonsensitive(local.storage_service_entry_manifest)}\nYAML"
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "null_resource" "istio_pod_monitors" {
  count = var.enabled && var.enable_prometheus_stack && var.enable_istio_pod_monitors ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.istio_pod_monitors_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete podmonitor istio-ztunnel istio-proxies istiod -n ${var.namespace} --ignore-not-found && ${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.istio_pod_monitors_manifest}\nYAML"
  }

  depends_on = [helm_release.prometheus_stack]
}

resource "null_resource" "kiali_route" {
  count = var.enabled && var.enable_kiali ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.kiali_route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.kiali_route_manifest}\nYAML"
  }

  depends_on = [helm_release.kiali]
}

resource "null_resource" "grafana_route" {
  count = var.enabled && var.enable_prometheus_stack ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.grafana_route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.grafana_route_manifest}\nYAML"
  }

  depends_on = [helm_release.prometheus_stack]
}

resource "null_resource" "prometheus_route" {
  count = var.enabled && var.enable_prometheus_stack && var.enable_prometheus_route && var.oauth2_proxy != null ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.prometheus_route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.prometheus_route_manifest}\nYAML"
  }

  depends_on = [helm_release.prometheus_oauth2_proxy]
}

resource "null_resource" "tracing_route" {
  count = var.enabled && (var.enable_tempo || var.enable_jaeger) ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.tracing_route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.tracing_route_manifest}\nYAML"
  }

  depends_on = [helm_release.tempo, helm_release.jaeger]
}

resource "null_resource" "legacy_jaeger_route_cleanup" {
  count = var.enabled ? 1 : 0

  triggers = {
    namespace = var.namespace
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} delete httproute jaeger -n ${var.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.tracing_route]
}
