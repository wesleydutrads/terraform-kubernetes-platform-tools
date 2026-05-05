locals {
  kubeconfig_path       = pathexpand(var.kubeconfig_path)
  oidc_issuer_host      = var.oauth2_proxy == null ? null : regex("^https?://([^/]+)", nonsensitive(var.oauth2_proxy.issuer_url))[0]
  storage_endpoint_host = var.storage == null ? null : nonsensitive(replace(replace(var.storage.endpoint, "https://", ""), "http://", ""))
  service_entry_hosts   = distinct(compact([var.host, local.oidc_issuer_host, local.storage_endpoint_host]))
  service_entry_host_block = join("\n", [
    for host in local.service_entry_hosts : "        - ${host}"
  ])
  route_manifest         = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: pyroscope
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
        - ${var.host}
      rules:
        - backendRefs:
            - name: pyroscope-oauth2-proxy
              port: 80
    YAML
  service_entry_manifest = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: pyroscope-public-and-storage
      namespace: ${var.istio_root_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
${local.service_entry_host_block}
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

resource "helm_release" "pyroscope" {
  count            = var.enabled ? 1 : 0
  name             = "pyroscope"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "pyroscope"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false

  values = [
    yamlencode({
      pyroscope = {
        disableSelfProfile = false
        extraArgs = {
          "log.level"                      = "info"
          "pyroscopedb.max-block-duration" = "30m"
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "768Mi"
          }
        }
        persistence = {
          enabled = false
        }
        config = var.storage == null ? "" : <<-YAML
          storage:
            backend: s3
            s3:
              endpoint: "${nonsensitive(replace(var.storage.endpoint, "https://", ""))}"
              region: "${nonsensitive(var.storage.region)}"
              bucket_name: "${nonsensitive(var.storage.bucket_name)}"
              access_key_id: "${nonsensitive(var.storage.access_key_id)}"
              secret_access_key: "${var.storage.secret_access_key}"
              bucket_lookup_type: path-style
        YAML
      }
      architecture = {
        storage = {
          v1 = true
          v2 = false
        }
        microservices = {
          enabled = false
        }
      }
      minio = {
        enabled = false
      }
      alloy = {
        enabled = true
        controller = {
          type     = "statefulset"
          replicas = 1
        }
      }
      serviceMonitor = {
        enabled = true
        labels = {
          release = "monitoring"
        }
      }
    })
  ]
}

resource "helm_release" "oauth2_proxy" {
  count            = var.enabled && var.enable_route && var.oauth2_proxy != null ? 1 : 0
  name             = "pyroscope-oauth2-proxy"
  repository       = "https://oauth2-proxy.github.io/manifests"
  chart            = "oauth2-proxy"
  version          = var.oauth2_proxy_chart_version
  namespace        = var.namespace
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
        "redirect-url"         = "https://${var.host}/oauth2/callback"
        upstream               = "http://pyroscope.${var.namespace}.svc.cluster.local:4040"
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

  depends_on = [helm_release.pyroscope]
}

resource "null_resource" "route" {
  count = var.enabled && var.enable_route && var.oauth2_proxy != null ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.route_manifest)
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.route_manifest}\nYAML"
  }

  depends_on = [helm_release.oauth2_proxy]
}

resource "null_resource" "service_entry" {
  count = var.enabled && length(local.service_entry_hosts) > 0 ? 1 : 0

  triggers = {
    manifest_sha    = sha1(local.service_entry_manifest)
    kubeconfig_path = local.kubeconfig_path
    kubectl_path    = var.kubectl_path
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.service_entry_manifest}\nYAML"
  }
}
