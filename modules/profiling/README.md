# profiling

Installs Grafana Pyroscope for continuous profiling and exposes the UI through
`oauth2-proxy` when requested.

## Architecture

```mermaid
flowchart LR
  User[Browser] --> Gateway[Istio public Gateway]
  Gateway --> Proxy[oauth2-proxy]
  Proxy --> Keycloak[Keycloak OIDC]
  Proxy --> Pyroscope[Pyroscope]
  Grafana[Grafana Profiles Drilldown] --> Pyroscope
  Pyroscope --> ObjectStorage[(OCI Object Storage S3)]
  Workloads[Profiled workloads] --> Pyroscope
```

## Profiles Drilldown Lab

Set `enable_ebpf_lab = true` to install a CPU-bound Python workload and a
privileged Grafana Alloy DaemonSet based on the official Grafana Pyroscope eBPF
Kubernetes example.

- Reference: `github.com/grafana/pyroscope/examples/grafana-alloy-auto-instrumentation/ebpf/kubernetes`
- Namespace: `pyroscope-ebpf`
- Profile service: `pyroscope-ebpf/python-fast-slow`
- Query: `process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name="pyroscope-ebpf/python-fast-slow"}`

The lab sends profiles to `http://pyroscope.<namespace>.svc.cluster.local:4040`.
It is intended for validation and hands-on training, not production traffic.

Set `enable_go_pprof_lab = true` to install a Go runtime pprof pull-mode lab.
This complements eBPF by exposing runtime-specific profile types through
the standard `/debug/pprof` endpoints. The lab intentionally uses only the Go
standard library, so it validates pull-mode profiling without requiring SDK
changes or extra application dependencies.

- Reference: `github.com/grafana/pyroscope/examples/grafana-alloy-auto-instrumentation/golang-pull`
- Namespace: `pyroscope-go-pprof`
- Profile service: `pyroscope-go/go-pprof-lab`
- CPU query: `process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name="pyroscope-go/go-pprof-lab"}`
- Memory query: `memory:alloc_space:bytes:space:bytes{service_name="pyroscope-go/go-pprof-lab"}`
- Goroutine query: `goroutine:goroutine:count:goroutine:count{service_name="pyroscope-go/go-pprof-lab"}`
- Mutex query: `mutex:contentions:count:contentions:count{service_name="pyroscope-go/go-pprof-lab"}`
- Block query: `block:contentions:count:contentions:count{service_name="pyroscope-go/go-pprof-lab"}`
- Expected standard pprof profile types: CPU, heap memory, mutex, block, and goroutine.

## Notes

- Use single-binary Pyroscope for Always Free clusters.
- Keep the public UI behind Keycloak; Pyroscope has no native OIDC login.
- Use Object Storage for profile blocks to avoid consuming block volume quota.
- Profile data only appears for workloads that expose profiles or push data.
