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
      labels:
        platform.wesleydutra.online/exposure-class: administrative
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
        disableSelfProfile = true
        extraArgs = merge({
          "log.level"                      = "info"
          "pyroscopedb.max-block-duration" = "30m"
          }, var.compactor_blocks_retention_period_seconds == null ? {} : {
          "compactor.blocks-retention-period" = "${var.compactor_blocks_retention_period_seconds}s"
        })
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

resource "kubernetes_namespace_v1" "ebpf_lab" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name = var.ebpf_lab_namespace
    labels = merge(
      {
        "app.kubernetes.io/name"    = "pyroscope-ebpf-lab"
        "app.kubernetes.io/part-of" = "profiling-labs"
      },
      var.ebpf_lab_use_central_waypoint ? {
        "istio.io/dataplane-mode"         = "ambient"
        "istio.io/use-waypoint"           = var.central_egress_waypoint_name
        "istio.io/use-waypoint-namespace" = var.istio_root_namespace
      } : {}
    )
  }
}

resource "kubernetes_config_map_v1" "ebpf_lab_python_app" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name      = "python-fast-slow"
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "python-fast-slow"
      "app.kubernetes.io/part-of" = "pyroscope-ebpf-lab"
    }
  }

  data = {
    "main.py" = <<-PY
      #!/usr/bin/env python3

      def work(n):
          i = 0
          while i < n:
              i += 1

      def fast_function():
          work(20000)

      def slow_function():
          work(80000)

      if __name__ == "__main__":
          while True:
              fast_function()
              slow_function()
    PY
  }
}

resource "kubernetes_deployment_v1" "ebpf_lab_python_app" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name      = "python-fast-slow"
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "python-fast-slow"
      "app.kubernetes.io/part-of"   = "pyroscope-ebpf-lab"
      "app.kubernetes.io/version"   = "v1"
      "pyroscope.io/profile_target" = "true"
      "pyroscope.io/profile_source" = "grafana-alloy-ebpf"
    }
    annotations = {
      "pyroscope.io/service_name"   = "pyroscope-ebpf/python-fast-slow"
      "pyroscope.io/reference_repo" = "github.com/grafana/pyroscope"
      "pyroscope.io/reference_path" = "examples/grafana-alloy-auto-instrumentation/ebpf/kubernetes"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "python-fast-slow"
      }
    }

    template {
      metadata {
        labels = {
          app                           = "python-fast-slow"
          "app.kubernetes.io/name"      = "python-fast-slow"
          "app.kubernetes.io/part-of"   = "pyroscope-ebpf-lab"
          "app.kubernetes.io/version"   = "v1"
          "pyroscope.io/profile_target" = "true"
        }
        annotations = {
          "pyroscope.io/service_name"   = "pyroscope-ebpf/python-fast-slow"
          "pyroscope.io/reference_repo" = "github.com/grafana/pyroscope"
          "pyroscope.io/reference_path" = "examples/grafana-alloy-auto-instrumentation/ebpf/kubernetes"
        }
      }

      spec {
        container {
          name              = "python-fast-slow"
          image             = var.ebpf_lab_python_image
          image_pull_policy = "IfNotPresent"
          command           = ["python3"]
          args              = ["/app/main.py"]

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "96Mi"
            }
          }

          volume_mount {
            name       = "app"
            mount_path = "/app"
            read_only  = true
          }
        }

        volume {
          name = "app"
          config_map {
            name = kubernetes_config_map_v1.ebpf_lab_python_app[0].metadata[0].name
            items {
              key  = "main.py"
              path = "main.py"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account_v1" "ebpf_lab_alloy" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name      = "pyroscope-ebpf-alloy"
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "pyroscope-ebpf-alloy"
      "app.kubernetes.io/part-of" = "pyroscope-ebpf-lab"
    }
  }
}

resource "kubernetes_cluster_role_v1" "ebpf_lab_alloy" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name = "${var.ebpf_lab_namespace}-alloy-discovery"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "ebpf_lab_alloy" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name = "${var.ebpf_lab_namespace}-alloy-discovery"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.ebpf_lab_alloy[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ebpf_lab_alloy[0].metadata[0].name
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "ebpf_lab_alloy" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name      = "pyroscope-ebpf-alloy"
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "pyroscope-ebpf-alloy"
      "app.kubernetes.io/part-of" = "pyroscope-ebpf-lab"
    }
  }

  data = {
    "config.alloy" = <<-ALLOY
      logging {
        level  = "info"
        format = "logfmt"
      }

      discovery.kubernetes "local_pods" {
        selectors {
          field = "spec.nodeName=" + env("HOSTNAME")
          role  = "pod"
        }
        role = "pod"
      }

      discovery.relabel "profile_targets" {
        targets = discovery.kubernetes.local_pods.targets

        rule {
          action        = "keep"
          source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name", "__meta_kubernetes_pod_label_pyroscope_io_profile_target"]
          separator     = ";"
          regex         = "${var.ebpf_lab_namespace};python-fast-slow;true"
        }

        rule {
          action        = "replace"
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }

        rule {
          action        = "replace"
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }

        rule {
          action        = "replace"
          source_labels = ["__meta_kubernetes_pod_node_name"]
          target_label  = "node"
        }

        rule {
          action        = "replace"
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }

        rule {
          action       = "replace"
          replacement  = "pyroscope-ebpf/python-fast-slow"
          target_label = "service_name"
        }

        rule {
          action       = "replace"
          replacement  = "pyroscope-ebpf"
          target_label = "service_namespace"
        }

        rule {
          action       = "replace"
          replacement  = "v1"
          target_label = "service_version"
        }

        rule {
          action       = "replace"
          replacement  = "grafana-pyroscope-official-ebpf-kubernetes"
          target_label = "lab"
        }
      }

      pyroscope.ebpf "python_fast_slow" {
        forward_to     = [pyroscope.write.endpoint.receiver]
        targets        = discovery.relabel.profile_targets.output
        python_enabled = true
      }

      pyroscope.write "endpoint" {
        endpoint {
          url = "http://pyroscope.${var.namespace}.svc.cluster.local:4040"
        }
      }
    ALLOY
  }
}

resource "kubernetes_daemon_set_v1" "ebpf_lab_alloy" {
  count = var.enabled && var.enable_ebpf_lab ? 1 : 0

  metadata {
    name      = "pyroscope-ebpf-alloy"
    namespace = kubernetes_namespace_v1.ebpf_lab[0].metadata[0].name
    labels = {
      app                         = "pyroscope-ebpf-alloy"
      "app.kubernetes.io/name"    = "pyroscope-ebpf-alloy"
      "app.kubernetes.io/part-of" = "pyroscope-ebpf-lab"
      "app.kubernetes.io/version" = "latest"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "pyroscope-ebpf-alloy"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "pyroscope-ebpf-alloy"
          "app.kubernetes.io/name"    = "pyroscope-ebpf-alloy"
          "app.kubernetes.io/part-of" = "pyroscope-ebpf-lab"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.ebpf_lab_alloy[0].metadata[0].name
        host_pid             = true

        container {
          name              = "alloy"
          image             = var.ebpf_lab_alloy_image
          image_pull_policy = "Always"
          command = [
            "/bin/alloy",
            "run",
            "/etc/alloy/config.alloy",
            "--server.http.listen-addr=0.0.0.0:12345"
          ]

          env {
            name = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          port {
            name           = "http-metrics"
            container_port = 12345
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          security_context {
            privileged  = true
            run_as_user = 0
          }

          volume_mount {
            name       = "alloy-config"
            mount_path = "/etc/alloy"
            read_only  = true
          }
        }

        volume {
          name = "alloy-config"
          config_map {
            name = kubernetes_config_map_v1.ebpf_lab_alloy[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.pyroscope,
    kubernetes_cluster_role_binding_v1.ebpf_lab_alloy,
    kubernetes_deployment_v1.ebpf_lab_python_app
  ]
}

resource "kubernetes_namespace_v1" "go_pprof_lab" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name = var.go_pprof_lab_namespace
    labels = merge(
      {
        "app.kubernetes.io/name"    = "go-pprof-lab"
        "app.kubernetes.io/part-of" = "profiling-labs"
      },
      var.go_pprof_lab_use_central_waypoint ? {
        "istio.io/dataplane-mode"         = "ambient"
        "istio.io/use-waypoint"           = var.central_egress_waypoint_name
        "istio.io/use-waypoint-namespace" = var.istio_root_namespace
      } : {}
    )
  }
}

resource "kubernetes_config_map_v1" "go_pprof_lab_app" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name      = "go-pprof-lab"
    namespace = kubernetes_namespace_v1.go_pprof_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "go-pprof-lab"
      "app.kubernetes.io/part-of" = "pyroscope-go-pprof-lab"
    }
  }

  data = {
    "main.go" = <<-GO
      package main

      import (
      	"log"
      	"net/http"
      	_ "net/http/pprof"
      	"runtime"
      	"sync"
      	"time"
      )

      var retained [][]byte
      var retainedMu sync.Mutex
      var mutexHotspot sync.Mutex

      func cpuWork() {
      	for {
      		x := 0
      		for i := 0; i < 4000000; i++ {
      			x += i % 97
      		}
      		if x == -1 {
      			log.Println("unreachable")
      		}
      	}
      }

      func heapWork() {
      	for {
      		buf := make([]byte, 256*1024)
      		for i := range buf {
      			buf[i] = byte(i)
      		}
      		retainedMu.Lock()
      		retained = append(retained, buf)
      		if len(retained) > 48 {
      			retained = retained[1:]
      		}
      		retainedMu.Unlock()
      		time.Sleep(200 * time.Millisecond)
      	}
      }

      func mutexHolder() {
      	for {
      		mutexHotspot.Lock()
      		time.Sleep(20 * time.Millisecond)
      		mutexHotspot.Unlock()
      		time.Sleep(1 * time.Millisecond)
      	}
      }

      func mutexWaiter() {
      	for {
      		mutexHotspot.Lock()
      		mutexHotspot.Unlock()
      		time.Sleep(1 * time.Millisecond)
      	}
      }

      func blockWork(ch <-chan struct{}) {
      	for {
      		<-ch
      		time.Sleep(1 * time.Millisecond)
      	}
      }

      func main() {
      	runtime.SetMutexProfileFraction(1)
      	runtime.SetBlockProfileRate(1)

      	for i := 0; i < 4; i++ {
      		go cpuWork()
      	}
      	go heapWork()
      	go mutexHolder()
      	for i := 0; i < 8; i++ {
      		go mutexWaiter()
      	}
      	ch := make(chan struct{})
      	for i := 0; i < 12; i++ {
      		go blockWork(ch)
      	}
      	go func() {
      		for {
      			time.Sleep(2 * time.Millisecond)
      			ch <- struct{}{}
      		}
      	}()

      	log.Println("go pprof lab listening on :6060")
      	log.Fatal(http.ListenAndServe(":6060", nil))
      }
    GO
  }
}

resource "kubernetes_deployment_v1" "go_pprof_lab_app" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name      = "go-pprof-lab"
    namespace = kubernetes_namespace_v1.go_pprof_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "go-pprof-lab"
      "app.kubernetes.io/part-of"   = "pyroscope-go-pprof-lab"
      "app.kubernetes.io/version"   = "v1"
      "pyroscope.io/profile_target" = "true"
      "pyroscope.io/profile_source" = "grafana-alloy-go-pull"
    }
    annotations = {
      "pyroscope.io/service_name"   = "pyroscope-go/go-pprof-lab"
      "pyroscope.io/reference_repo" = "github.com/grafana/pyroscope"
      "pyroscope.io/reference_path" = "examples/grafana-alloy-auto-instrumentation/golang-pull"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "go-pprof-lab"
      }
    }

    template {
      metadata {
        labels = {
          app                           = "go-pprof-lab"
          "app.kubernetes.io/name"      = "go-pprof-lab"
          "app.kubernetes.io/part-of"   = "pyroscope-go-pprof-lab"
          "app.kubernetes.io/version"   = "v1"
          "pyroscope.io/profile_target" = "true"
        }
        annotations = {
          "pyroscope.io/service_name"   = "pyroscope-go/go-pprof-lab"
          "pyroscope.io/reference_repo" = "github.com/grafana/pyroscope"
          "pyroscope.io/reference_path" = "examples/grafana-alloy-auto-instrumentation/golang-pull"
          "checksum/config"             = sha256(jsonencode(kubernetes_config_map_v1.go_pprof_lab_app[0].data))
        }
      }

      spec {
        container {
          name              = "go-pprof-lab"
          image             = var.go_pprof_lab_go_image
          image_pull_policy = "IfNotPresent"
          command           = ["go"]
          args              = ["run", "/app/main.go"]

          port {
            name           = "pprof"
            container_port = 6060
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "96Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "app"
            mount_path = "/app"
            read_only  = true
          }
        }

        volume {
          name = "app"
          config_map {
            name = kubernetes_config_map_v1.go_pprof_lab_app[0].metadata[0].name
            items {
              key  = "main.go"
              path = "main.go"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "go_pprof_lab_app" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name      = "go-pprof-lab"
    namespace = kubernetes_namespace_v1.go_pprof_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "go-pprof-lab"
      "app.kubernetes.io/part-of" = "pyroscope-go-pprof-lab"
    }
  }

  spec {
    selector = {
      app = "go-pprof-lab"
    }

    port {
      name        = "pprof"
      port        = 6060
      target_port = "pprof"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_config_map_v1" "go_pprof_lab_alloy" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name      = "go-pprof-alloy"
    namespace = kubernetes_namespace_v1.go_pprof_lab[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "go-pprof-alloy"
      "app.kubernetes.io/part-of" = "pyroscope-go-pprof-lab"
    }
  }

  data = {
    "config.alloy" = <<-ALLOY
      logging {
        level  = "info"
        format = "logfmt"
      }

      pyroscope.write "endpoint" {
        endpoint {
          url = "http://pyroscope.${var.namespace}.svc.cluster.local:4040"
        }
        external_labels = {
          lab = "grafana-pyroscope-official-go-pull",
        }
      }

      pyroscope.scrape "go_pprof_lab" {
        targets = [
          {
            "__address__"       = "go-pprof-lab.${var.go_pprof_lab_namespace}.svc.cluster.local:6060",
            "service_name"      = "pyroscope-go/go-pprof-lab",
            "service_namespace" = "pyroscope-go",
            "service_version"   = "v1",
          },
        ]
        forward_to = [pyroscope.write.endpoint.receiver]

        profiling_config {
          profile.process_cpu {
            enabled = true
          }

          profile.godeltaprof_memory {
            enabled = false
          }

          profile.memory {
            enabled = true
          }

          profile.godeltaprof_mutex {
            enabled = false
          }

          profile.mutex {
            enabled = true
          }

          profile.godeltaprof_block {
            enabled = false
          }

          profile.block {
            enabled = true
          }

          profile.goroutine {
            enabled = true
          }
        }
      }
    ALLOY
  }
}

resource "kubernetes_deployment_v1" "go_pprof_lab_alloy" {
  count = var.enabled && var.enable_go_pprof_lab ? 1 : 0

  metadata {
    name      = "go-pprof-alloy"
    namespace = kubernetes_namespace_v1.go_pprof_lab[0].metadata[0].name
    labels = {
      app                         = "go-pprof-alloy"
      "app.kubernetes.io/name"    = "go-pprof-alloy"
      "app.kubernetes.io/part-of" = "pyroscope-go-pprof-lab"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "go-pprof-alloy"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "go-pprof-alloy"
          "app.kubernetes.io/name"    = "go-pprof-alloy"
          "app.kubernetes.io/part-of" = "pyroscope-go-pprof-lab"
        }
        annotations = {
          "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.go_pprof_lab_alloy[0].data))
        }
      }

      spec {
        container {
          name              = "alloy"
          image             = var.go_pprof_lab_alloy_image
          image_pull_policy = "Always"
          command = [
            "/bin/alloy",
            "run",
            "/etc/alloy/config.alloy",
            "--server.http.listen-addr=0.0.0.0:12345"
          ]

          port {
            name           = "http-metrics"
            container_port = 12345
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "192Mi"
            }
          }

          volume_mount {
            name       = "alloy-config"
            mount_path = "/etc/alloy"
            read_only  = true
          }
        }

        volume {
          name = "alloy-config"
          config_map {
            name = kubernetes_config_map_v1.go_pprof_lab_alloy[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.pyroscope,
    kubernetes_service_v1.go_pprof_lab_app
  ]
}
