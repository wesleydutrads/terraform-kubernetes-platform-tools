# lab-apps

Installs optional workloads used to validate the platform observability stack.
This module intentionally keeps lab workloads separate from production platform
tools.

## Features

- OpenTelemetry Demo Helm chart.
- Public `HTTPRoute` for the demo frontend.
- `ServiceEntry` for the public demo hostname.
- Optional OpenTelemetry auto-instrumentation annotations for Istio Bookinfo.
- Optional enrollment of the demo namespace into the shared ambient waypoint.

## Usage

```hcl
module "lab_apps" {
  source = "../terraform-kubernetes-platform-tools/modules/lab-apps"

  enabled                          = true
  gateway_name                     = module.platform.gateway_name
  gateway_namespace                = module.platform.gateway_namespace
  opentelemetry_instrumentation_ref = module.observability.opentelemetry_instrumentation_ref
  opentelemetry_collector_endpoint = module.observability.opentelemetry_collector_endpoint
  enable_opentelemetry_demo        = true
  enable_opentelemetry_demo_route  = true
  hosts = {
    grafana = "grafana.example.com"
  }
}
```
