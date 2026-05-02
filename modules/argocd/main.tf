locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  oidc_enabled    = var.oidc != null

  route_manifest = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: argocd
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
            - name: argocd-server
              port: 80
    YAML

  service_entry_manifest = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: argocd-public-host
      namespace: ${var.namespace}
    spec:
      hosts:
        - ${var.host}
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

resource "kubernetes_namespace_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.namespace
    labels = var.enable_ambient ? {
      "istio.io/dataplane-mode" = "ambient"
    } : {}
  }
}

resource "helm_release" "this" {
  count            = var.enabled ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      global = {
        domain = var.host
      }
      configs = merge({
        params = {
          "server.insecure" = true
        }
        cm = merge({
          "admin.enabled" = tostring(var.admin_enabled)
          }, local.oidc_enabled ? {
          url = "https://${var.host}"
          "oidc.config" = yamlencode({
            name         = "Keycloak"
            issuer       = var.oidc.issuer_url
            clientID     = var.oidc.client_id
            clientSecret = "$oidc.keycloak.clientSecret"
            requestedScopes = [
              "openid",
              "profile",
              "email",
              "groups"
            ]
          })
        } : {})
        }, jsondecode(local.oidc_enabled ? jsonencode({
          rbac = {
            "policy.csv" = <<-CSV
            g, ${var.oidc.admin_group}, role:admin
            g, ${var.oidc.readonly_group}, role:readonly
          CSV
            "scopes"     = "[groups]"
          }
          secret = {
            extra = {
              "oidc.keycloak.clientSecret" = var.oidc.client_secret
            }
          }
      }) : "{}"))
      server = {
        extraArgs = ["--insecure"]
        service = {
          type = "ClusterIP"
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      controller = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "750m"
            memory = "768Mi"
          }
        }
      }
      repoServer = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      applicationSet = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      redis = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      dex = {
        enabled = true
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      notifications = {
        enabled = false
      }
    })
  ]
}

resource "null_resource" "route" {
  count = var.enabled ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.route_manifest}\nYAML"
  }

  depends_on = [helm_release.this]
}

resource "null_resource" "public_host_service_entry" {
  count = var.enabled && var.enable_public_host_service_entry ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.service_entry_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.service_entry_manifest}\nYAML"
  }

  depends_on = [helm_release.this]
}
