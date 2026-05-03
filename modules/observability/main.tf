locals {
  kubeconfig_path             = pathexpand(var.kubeconfig_path)
  tracing_host                = var.hosts.tracing
  tracing_backend             = var.enable_tempo ? "monitoring-grafana" : "jaeger"
  tracing_backend_port        = var.enable_tempo ? 80 : 16686
  oidc_issuer_host            = local.oidc_enabled ? regex("^https?://([^/]+)", var.oidc.issuer_url)[0] : null
  monitoring_public_hosts     = distinct([var.hosts.kiali, var.hosts.grafana, local.tracing_host])
  egress_public_hosts         = distinct(compact(concat(local.monitoring_public_hosts, [local.oidc_issuer_host])))
  public_hosts_policy         = join("\n", [for host in local.monitoring_public_hosts : "                  - ${host}"])
  public_hosts_service_entry  = join("\n", [for host in local.egress_public_hosts : "        - ${host}"])
  oidc_enabled                = var.oidc != null
  loki_storage_endpoint_host  = var.loki_storage == null ? null : nonsensitive(replace(replace(var.loki_storage.endpoint, "https://", ""), "http://", ""))
  tempo_storage_endpoint_host = var.tempo_storage == null ? null : nonsensitive(replace(replace(var.tempo_storage.endpoint, "https://", ""), "http://", ""))
  storage_endpoint_hosts      = distinct(compact([local.loki_storage_endpoint_host, local.tempo_storage_endpoint_host]))
  storage_service_entry_hosts = join("\n", [for host in local.storage_endpoint_hosts : "        - ${host}"])
  kiali_discovery_override    = local.oidc_enabled ? try(var.oidc.kiali_discovery_override, null) : null
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
  token_policy_manifest              = <<-YAML
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
  public_host_service_entry_manifest = <<-YAML
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
  storage_service_entry_manifest     = <<-YAML
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
  istio_pod_monitors_manifest        = <<-YAML
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
  kiali_route_manifest               = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: kiali
      namespace: ${var.namespace}
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
        - ${var.hosts.kiali}
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
  grafana_route_manifest             = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: grafana
      namespace: ${var.namespace}
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
        - ${var.hosts.grafana}
      rules:
        - backendRefs:
            - name: monitoring-grafana
              port: 80
    YAML
  tracing_route_manifest             = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: tracing
      namespace: ${var.namespace}
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
        - ${local.tracing_host}
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
                    { key = "namespace" },
                    { key = "pod" },
                    { key = "service.name", value = "service_name" },
                  ]
                  filterByTraceID = true
                  filterBySpanID  = false
                }
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
        persistence = {
          enabled = false
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
          }
        ]
        snippets = {
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
  count            = var.enabled && var.enable_kiali ? 1 : 0
  name             = "kiali"
  repository       = "https://kiali.org/helm-charts"
  chart            = "kiali-server"
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
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
        signing_key        = var.monitoring_token
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
          health_check_url = var.enable_tempo ? "http://tempo.${var.namespace}.svc.cluster.local:3200" : "http://jaeger.${var.namespace}.svc:16686"
          external_url     = "https://${local.tracing_host}"
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

  depends_on = [kubernetes_secret_v1.kiali_oidc]
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
