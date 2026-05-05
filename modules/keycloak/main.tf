resource "random_password" "admin" {
  count = var.enabled && var.admin_password == null ? 1 : 0

  length  = 24
  special = false
}

resource "random_password" "database" {
  count = var.enabled && var.database_password == null ? 1 : 0

  length           = 24
  special          = true
  override_special = "#_-"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

locals {
  kubeconfig_path       = pathexpand(var.kubeconfig_path)
  admin_password        = var.admin_password != null ? var.admin_password : try(random_password.admin[0].result, null)
  database_password     = var.database_password != null ? var.database_password : try(random_password.database[0].result, null)
  database_service_host = "${var.database_external_name_service_name}.${var.namespace}.svc.cluster.local"
  database_host         = var.database_host != null ? var.database_host : ""
  database_url          = var.database_host != null ? "jdbc:mysql://${local.database_host}:${var.database_port}/${var.database_name}" : ""
  database_host_is_ip   = var.database_host != null ? can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.database_host)) : false

  route_manifest = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: keycloak
      namespace: ${var.namespace}
      labels:
        platform.wesleydutra.online/exposure-class: identity
        platform.wesleydutra.online/auth: native
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
            - name: keycloak
              port: 8080
    YAML

  service_entry_manifest = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: keycloak-public-host
      namespace: ${var.gateway_namespace}
    spec:
      exportTo:
        - "*"
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

  database_service_entry_manifest_static = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: keycloak-mysql
      namespace: ${var.gateway_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
        - keycloak-mysql.mesh-external.local
      addresses:
        - ${var.database_host}/32
      location: MESH_EXTERNAL
      ports:
        - number: ${var.database_port}
          name: mysql
          protocol: TCP
      resolution: STATIC
      endpoints:
        - address: ${var.database_host}
    YAML

  database_service_entry_manifest_dns = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: keycloak-mysql
      namespace: ${var.gateway_namespace}
    spec:
      exportTo:
        - "*"
      hosts:
        - ${var.database_host}
      location: MESH_EXTERNAL
      ports:
        - number: ${var.database_port}
          name: mysql
          protocol: TCP
      resolution: DNS
    YAML

  database_service_entry_manifest = var.database_host == null ? "" : local.database_host_is_ip ? local.database_service_entry_manifest_static : local.database_service_entry_manifest_dns
}

resource "kubernetes_namespace_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.namespace
    labels = var.enable_ambient ? {
      "istio.io/dataplane-mode" = "ambient"
    } : {}
  }

  lifecycle {
    ignore_changes = [metadata[0].labels]
  }
}

resource "kubernetes_secret_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "keycloak-secrets"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  data = {
    KC_BOOTSTRAP_ADMIN_PASSWORD = local.admin_password
    KC_DB_PASSWORD              = local.database_password
    MYSQL_ADMIN_PASSWORD        = var.database_admin_password != null ? var.database_admin_password : ""
  }
}

resource "kubernetes_config_map_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "keycloak-config"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  data = {
    KC_DB                       = "mysql"
    KC_DB_URL                   = local.database_url
    KC_DB_USERNAME              = var.database_username
    KC_HOSTNAME                 = "https://${var.host}"
    KC_HTTP_ENABLED             = "true"
    KC_PROXY_HEADERS            = "xforwarded"
    KC_HEALTH_ENABLED           = "true"
    KC_METRICS_ENABLED          = "true"
    KC_BOOTSTRAP_ADMIN_USERNAME = var.admin_username
    MYSQL_ADMIN_USER            = var.database_admin_username != null ? var.database_admin_username : ""
    MYSQL_DATABASE              = var.database_name
    MYSQL_USER                  = var.database_username
    MYSQL_HOST                  = local.database_host
    MYSQL_PORT                  = tostring(var.database_port)
  }
}

resource "kubernetes_service_v1" "database_external_name" {
  count = var.enabled && var.database_host != null && var.enable_database_external_name_service ? 1 : 0

  metadata {
    name      = var.database_external_name_service_name
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  spec {
    type          = "ExternalName"
    external_name = var.database_host

    port {
      name        = "mysql"
      port        = var.database_port
      protocol    = "TCP"
      target_port = var.database_port
    }
  }
}

resource "kubernetes_job_v1" "database_bootstrap" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "keycloak-mysql-bootstrap"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  spec {
    backoff_limit = 10

    template {
      metadata {}

      spec {
        restart_policy = "OnFailure"

        container {
          name    = "mysql"
          image   = "docker.io/library/mysql:8.4"
          command = ["/bin/sh", "-ec"]
          args = [
            "mysql -h \"$MYSQL_HOST\" -P \"$MYSQL_PORT\" -u \"$MYSQL_ADMIN_USER\" -p\"$MYSQL_ADMIN_PASSWORD\" -e \"CREATE DATABASE IF NOT EXISTS \\`$${MYSQL_DATABASE}\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS '$${MYSQL_USER}'@'%' IDENTIFIED BY '$${KC_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON \\`$${MYSQL_DATABASE}\\`.* TO '$${MYSQL_USER}'@'%'; FLUSH PRIVILEGES;\""
          ]

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.this[0].metadata[0].name
            }
          }

          env {
            name = "MYSQL_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this[0].metadata[0].name
                key  = "MYSQL_ADMIN_PASSWORD"
              }
            }
          }

          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this[0].metadata[0].name
                key  = "KC_DB_PASSWORD"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [kubernetes_secret_v1.this[0]]

    precondition {
      condition     = var.database_host != null && var.database_admin_username != null && var.database_admin_password != null
      error_message = "database_host, database_admin_username, and database_admin_password are required when Keycloak is enabled."
    }
  }
}

resource "kubernetes_deployment_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    labels = {
      app = "keycloak"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "keycloak"
      }
    }

    template {
      metadata {
        annotations = {
          "checksum/config" = sha1(jsonencode(kubernetes_config_map_v1.this[0].data))
        }

        labels = {
          app = "keycloak"
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = var.image
          args  = ["start"]

          port {
            container_port = 8080
            name           = "http"
          }

          port {
            container_port = 9000
            name           = "management"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.this[0].metadata[0].name
            }
          }

          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this[0].metadata[0].name
                key  = "KC_DB_PASSWORD"
              }
            }
          }

          env {
            name = "KC_BOOTSTRAP_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this[0].metadata[0].name
                key  = "KC_BOOTSTRAP_ADMIN_PASSWORD"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 90
            period_seconds        = 10
            failure_threshold     = 18
          }

          liveness_probe {
            http_get {
              path = "/health/live"
              port = 9000
            }
            initial_delay_seconds = 180
            period_seconds        = 20
            failure_threshold     = 6
          }

          startup_probe {
            http_get {
              path = "/health/live"
              port = 9000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 36
          }

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }
        }
      }
    }
  }

  depends_on = [kubernetes_job_v1.database_bootstrap]
}

resource "kubernetes_service_v1" "this" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }

  spec {
    selector = {
      app = "keycloak"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }

    port {
      name        = "management"
      port        = 9000
      target_port = "management"
    }
  }
}

resource "null_resource" "route" {
  count = var.enabled ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.route_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.route_manifest}\nYAML"
  }

  depends_on = [kubernetes_service_v1.this]
}

resource "null_resource" "public_host_service_entry" {
  count = var.enabled && var.enable_public_host_service_entry ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.service_entry_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.service_entry_manifest}\nYAML"
  }

  depends_on = [kubernetes_service_v1.this]
}

resource "null_resource" "database_service_entry" {
  count = var.enabled && var.database_host != null ? 1 : 0

  triggers = {
    manifest_sha = sha1(local.database_service_entry_manifest)
  }

  provisioner "local-exec" {
    command = "${var.kubectl_path} --kubeconfig=${local.kubeconfig_path} apply -f - <<'YAML'\n${local.database_service_entry_manifest}\nYAML"
  }

  depends_on = [kubernetes_service_v1.this]
}
