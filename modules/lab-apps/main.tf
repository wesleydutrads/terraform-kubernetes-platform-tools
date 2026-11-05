locals {
  demo_hosts                                   = distinct(concat([local.opentelemetry_demo_host], lookup(var.additional_hosts, "opentelemetry_demo", [])))
  loadgen_hosts                                = distinct(concat([local.opentelemetry_loadgen_host], lookup(var.additional_hosts, "opentelemetry_loadgen", [])))
  kubeconfig_path                              = pathexpand(var.kubeconfig_path)
  opentelemetry_demo_host                      = coalesce(var.opentelemetry_demo_host, try(var.hosts.opentelemetry_demo, null), replace(var.hosts.grafana, "/^grafana\\./", "otel-demo."))
  opentelemetry_loadgen_host                   = coalesce(try(var.hosts.opentelemetry_loadgen, null), replace(var.hosts.grafana, "/^grafana\\./", "loadgen."))
  opentelemetry_collector_url                  = coalesce(var.opentelemetry_collector_endpoint, "http://otel-collector.observability.svc.cluster.local:4318")
  opentelemetry_collector_dns                  = replace(replace(local.opentelemetry_collector_url, "http://", ""), ":4318", "")
  opentelemetry_demo_route_manifest            = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: otel-demo
      namespace: ${var.opentelemetry_demo_namespace}
      labels:
        platform.wesleydutra.online/exposure-class: lab
        platform.wesleydutra.online/auth: public
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.demo_hosts~}
        - ${host}
%{endfor~}
      rules:
        - backendRefs:
            - name: frontend-proxy
              port: 8080
    YAML
  opentelemetry_loadgen_route_manifest         = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: otel-demo-loadgen
      namespace: ${var.opentelemetry_demo_namespace}
      labels:
        platform.wesleydutra.online/exposure-class: lab
        platform.wesleydutra.online/auth: oauth2-proxy
%{if var.external_dns_target != null~}
      annotations:
        external-dns.alpha.kubernetes.io/target: ${var.external_dns_target}
%{endif~}
    spec:
      parentRefs:
        - name: ${var.gateway_name}
          namespace: ${var.gateway_namespace}
      hostnames:
%{for host in local.loadgen_hosts~}
        - ${host}
%{endfor~}
      rules:
        - backendRefs:
            - name: load-generator-oauth2-proxy
              port: 80
    YAML
  opentelemetry_demo_service_entry_manifest    = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: otel-demo-public-host
      namespace: ${var.istio_root_namespace}
    spec:
      hosts:
%{for host in local.demo_hosts~}
        - ${host}
%{endfor~}
      location: MESH_EXTERNAL
      ports:
        - number: 443
          name: tls
          protocol: TLS
      resolution: DNS
    YAML
  opentelemetry_loadgen_service_entry_manifest = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: otel-demo-loadgen-public-host
      namespace: ${var.istio_root_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
%{for host in local.loadgen_hosts~}
        - ${host}
%{endfor~}
        - ${var.oauth2_proxy == null ? local.opentelemetry_loadgen_host : regex("^https?://([^/]+)", nonsensitive(var.oauth2_proxy.issuer_url))[0]}
%{for host in var.additional_egress_hosts~}
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

resource "kubernetes_namespace_v1" "opentelemetry_demo" {
  count = var.enabled && var.enable_opentelemetry_demo ? 1 : 0

  metadata {
    name = var.opentelemetry_demo_namespace
    labels = merge(
      {
        "istio.io/dataplane-mode" = "ambient"
      },
      var.opentelemetry_demo_use_central_waypoint ? {
        "istio.io/use-waypoint"           = var.central_egress_waypoint_name
        "istio.io/use-waypoint-namespace" = var.istio_root_namespace
      } : {}
    )
  }

  lifecycle {
    ignore_changes = [metadata[0].labels]
  }
}

resource "null_resource" "bookinfo_opentelemetry_annotations" {
  count = var.enabled && var.enable_bookinfo_opentelemetry_annotations && var.opentelemetry_instrumentation_ref != null ? 1 : 0

  triggers = {
    instrumentation_ref = var.opentelemetry_instrumentation_ref
    overlay_version     = "bookinfo-observability-v2"
    annotation_target   = "pod-template-v1"
    kubeconfig_path     = local.kubeconfig_path
    kubectl_path        = var.kubectl_path
  }

  provisioner "local-exec" {
    command = join(" && ", [
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment details-v1 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"details\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v1\"},\"annotations\":{\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v1\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment productpage-v1 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"productpage\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v1\"},\"annotations\":{\"instrumentation.opentelemetry.io/inject-python\":\"${var.opentelemetry_instrumentation_ref}\",\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v1\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment ratings-v1 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"ratings\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v1\"},\"annotations\":{\"instrumentation.opentelemetry.io/inject-nodejs\":\"${var.opentelemetry_instrumentation_ref}\",\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v1\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment reviews-v1 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"reviews\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v1\"},\"annotations\":{\"instrumentation.opentelemetry.io/inject-java\":\"${var.opentelemetry_instrumentation_ref}\",\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v1\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment reviews-v2 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"reviews\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v2\"},\"annotations\":{\"instrumentation.opentelemetry.io/inject-java\":\"${var.opentelemetry_instrumentation_ref}\",\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v2\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} patch deployment reviews-v3 -n default --type=merge -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"app.kubernetes.io/name\":\"reviews\",\"app.kubernetes.io/part-of\":\"bookinfo\",\"app.kubernetes.io/version\":\"v3\"},\"annotations\":{\"instrumentation.opentelemetry.io/inject-java\":\"${var.opentelemetry_instrumentation_ref}\",\"resource.opentelemetry.io/service.namespace\":\"bookinfo\",\"resource.opentelemetry.io/service.version\":\"v3\"}}}}}'",
      "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} rollout status deployment details-v1 productpage-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3 -n default --timeout=180s"
    ])
  }
}

resource "helm_release" "opentelemetry_demo" {
  count            = var.enabled && var.enable_opentelemetry_demo ? 1 : 0
  name             = "otel-demo"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-demo"
  version          = var.opentelemetry_demo_chart_version
  namespace        = kubernetes_namespace_v1.opentelemetry_demo[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      default = {
        envOverrides = [
          {
            name  = "OTEL_COLLECTOR_NAME"
            value = local.opentelemetry_collector_dns
          },
          {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = local.opentelemetry_collector_url
          },
          {
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "deployment.environment.name=lab,k8s.cluster.name=oke-always-free,service.namespace=otel-demo"
          }
        ]
      }
      components = {
        accounting = {
          initContainers = [
            {
              name    = "wait-for-kafka"
              image   = "docker.io/library/busybox:latest"
              command = ["sh", "-c", "until nc -z -v -w30 kafka 9092; do echo waiting for kafka; sleep 2; done;"]
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = var.opentelemetry_demo_accounting_memory_limit
            }
          }
        }
        cart = {
          initContainers = [
            {
              name    = "wait-for-valkey-cart"
              image   = "docker.io/library/busybox:latest"
              command = ["sh", "-c", "until nc -z -v -w30 valkey-cart 6379; do echo waiting for valkey-cart; sleep 2; done;"]
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "96Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "192Mi"
            }
          }
        }
        checkout = {
          initContainers = [
            {
              name    = "wait-for-kafka"
              image   = "docker.io/library/busybox:latest"
              command = ["sh", "-c", "until nc -z -v -w30 kafka 9092; do echo waiting for kafka; sleep 2; done;"]
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
        "fraud-detection" = {
          initContainers = [
            {
              name    = "wait-for-kafka"
              image   = "docker.io/library/busybox:latest"
              command = ["sh", "-c", "until nc -z -v -w30 kafka 9092; do echo waiting for kafka; sleep 2; done;"]
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "384Mi"
            }
          }
        }
        "load-generator" = {
          envOverrides = [
            {
              name  = "LOCUST_BROWSER_TRAFFIC_ENABLED"
              value = tostring(var.opentelemetry_demo_enable_browser_traffic)
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1536Mi"
            }
          }
        }
        flagd = {
          initContainers = [
            {
              name    = "init-config"
              image   = "docker.io/library/busybox:latest"
              command = ["sh", "-c", "cp /config-ro/demo.flagd.json /config-rw/demo.flagd.json && cat /config-rw/demo.flagd.json"]
              volumeMounts = [
                {
                  mountPath = "/config-ro"
                  name      = "config-ro"
                },
                {
                  mountPath = "/config-rw"
                  name      = "config-rw"
                }
              ]
            }
          ]
          resources = {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
        ad = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "384Mi"
            }
          }
        }
        email = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "128Mi"
            }
          }
        }
        frontend = {
          resources = {
            requests = {
              cpu    = "20m"
              memory = "192Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "384Mi"
            }
          }
        }
        currency = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
        "frontend-proxy" = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }
        }
        "image-provider" = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
        kafka = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "640Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "896Mi"
            }
          }
        }
        llm = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "96Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "192Mi"
            }
          }
        }
        payment = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "160Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
        "product-catalog" = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "96Mi"
            }
          }
        }
        "product-reviews" = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
        postgresql = {
          imageOverride = {
            repository = "docker.io/library/postgres"
            tag        = "17.6"
          }
          resources = {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "192Mi"
            }
          }
        }
        quote = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
        recommendation = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "512Mi"
            }
          }
        }
        shipping = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
        "valkey-cart" = {
          imageOverride = {
            repository = "docker.io/valkey/valkey"
            tag        = "9.0.1-alpine3.23"
          }
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "96Mi"
            }
          }
        }
      }
      "opentelemetry-collector" = {
        enabled = false
      }
      jaeger = {
        enabled = false
      }
      prometheus = {
        enabled = false
      }
      grafana = {
        enabled = false
      }
      opensearch = {
        enabled = false
      }
    })
  ]
}

resource "null_resource" "opentelemetry_demo_route" {
  count = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_demo_route ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.opentelemetry_demo_route_manifest)
    name            = "otel-demo"
    namespace       = var.opentelemetry_demo_namespace
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.opentelemetry_demo_route_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete httproute ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [helm_release.opentelemetry_demo]
}

resource "helm_release" "load_generator_oauth2_proxy" {
  count            = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_load_generator_route && var.oauth2_proxy != null ? 1 : 0
  name             = "load-generator-oauth2-proxy"
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = var.oauth2_proxy_chart_version
  namespace        = kubernetes_namespace_v1.opentelemetry_demo[0].metadata[0].name
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
        "redirect-url"         = "https://${local.opentelemetry_loadgen_host}/oauth2/callback"
        upstream               = "http://load-generator.${var.opentelemetry_demo_namespace}.svc.cluster.local:8089"
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
    })
  ]

  depends_on = [helm_release.opentelemetry_demo]
}

resource "null_resource" "opentelemetry_loadgen_route" {
  count = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_load_generator_route && var.oauth2_proxy != null ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.opentelemetry_loadgen_route_manifest)
    name            = "otel-demo-loadgen"
    namespace       = var.opentelemetry_demo_namespace
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.opentelemetry_loadgen_route_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete httproute ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [helm_release.load_generator_oauth2_proxy]
}

resource "null_resource" "opentelemetry_demo_public_host_service_entry" {
  count = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_demo_route ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.opentelemetry_demo_service_entry_manifest)
    name            = "otel-demo-public-host"
    namespace       = var.istio_root_namespace
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.opentelemetry_demo_service_entry_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete serviceentry ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.opentelemetry_demo_route]
}

resource "null_resource" "opentelemetry_loadgen_public_host_service_entry" {
  count = var.enabled && var.enable_opentelemetry_demo && var.enable_opentelemetry_load_generator_route && var.oauth2_proxy != null ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.opentelemetry_loadgen_service_entry_manifest)
    name            = "otel-demo-loadgen-public-host"
    namespace       = var.istio_root_namespace
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.opentelemetry_loadgen_service_entry_manifest}\nYAML"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "\"$${LAB_KUBECTL:?runtime kubectl required}\" --kubeconfig=\"$${KUBECONFIG:?runtime kubeconfig required}\" --context=\"$${LAB_KUBE_CONTEXT:?runtime context required}\" delete serviceentry ${self.triggers.name} -n ${self.triggers.namespace} --ignore-not-found"
  }

  depends_on = [null_resource.opentelemetry_loadgen_route]
}
