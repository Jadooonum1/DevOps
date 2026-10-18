# Observability Concepts

Notes that go with the hands-on part of this folder, using the library system as the running
example.

## Monitoring vs observability

**Monitoring** answers questions you decided on in advance: "is `catalog-api` up?", "is the
error rate above 5 %?". You choose the metrics, draw the dashboards and set the alert
thresholds before anything goes wrong.

**Observability** is about how well you can answer questions you did *not* plan for, using
only what the system already sends out. For example: "why are loan renewals slow only for
members of the east branch since Tuesday's release?". A system is observable when its
metrics, logs and traces carry enough context (labels, request IDs, versions) that you can
follow a new symptom to its cause without shipping new code to investigate.

Monitoring tells you *that* something is wrong. Observability lets you work out *why*.
You need both: alerts to wake someone up, and rich telemetry so that person can find the
cause quickly.

Why it matters more on Kubernetes: Pods are short-lived and rescheduled, IPs change, one
request passes through several services, and `kubectl logs` loses data as soon as a Pod is
deleted. Telemetry has to be collected centrally, and labelled so it can be matched up
afterwards.

## The three pillars

### Metrics

Numeric samples over time, identified by a name and labels, e.g.
`http_requests_total{service="catalog-api", status="500"}`.

- Cheap to store and fast to query, so they are ideal for dashboards, trends and alerting.
- Types (Prometheus): **counter** (only goes up: requests, errors), **gauge** (goes up and
  down: memory, queue length), **histogram/summary** (distributions: latency percentiles).
- Useful frameworks: **RED** for services (Rate, Errors, Duration) and **USE** for
  resources (Utilisation, Saturation, Errors).
- Limitation: aggregated. A metric can tell you that 3 % of requests fail, but not which
  request failed or why. Too many label values (user IDs, ISBNs) causes a *cardinality*
  explosion.

### Logs

Timestamped records of single events, written by the application: `ERROR payments
gateway unreachable, exiting`.

- They give the most detail: stack traces, input values, decisions the code made.
- **Structured** logs (JSON with fields like `level`, `member_id`, `trace_id`) can be
  filtered and aggregated. Plain text can only be searched with grep.
- Cost grows with volume. Loki keeps this cheap by indexing only the labels (namespace,
  pod, app) and not the full text.

### Traces

The path of one request through every service it touches, made of **spans** (one per
operation, each with a start time, duration and attributes) that share a **trace ID**.

- Example: `reader-web → catalog-api → loan-service → database`. The trace shows that
  480 ms of a 520 ms request was spent in one database query in `loan-service`.
- Requires instrumentation (OpenTelemetry SDKs or auto-instrumentation) and context
  propagation through headers (`traceparent`).
- Tools: Jaeger, Grafana Tempo, Zipkin. This lab does not deploy a tracing backend.

### Using them together

A typical investigation goes **metrics → traces → logs**:

1. An alert fires from a **metric** (`CatalogApiHighErrorRate`).
2. The dashboard shows *when* it started and *which* service and version are affected.
3. A **trace** of a failing request shows *where* in the call chain the time or error is.
4. The **logs** for that span (found by trace ID) show *why*: the exact error message.

Shared labels (`namespace`, `app`, `pod`) and a trace ID in every log line are what let
you jump from one signal to the next. That is why the Alloy config in this folder copies
Kubernetes metadata onto every log stream.

## Common tools

| Need | Tools |
|---|---|
| Metrics collection and storage | Prometheus, Grafana Mimir, Thanos, VictoriaMetrics |
| Kubernetes object state as metrics | kube-state-metrics |
| Node metrics | node-exporter |
| Short-term resource usage (`kubectl top`, HPA) | metrics-server |
| Alert routing, grouping, silencing | Alertmanager |
| Logs | Loki, Elasticsearch/OpenSearch (ELK/EFK) |
| Log/telemetry collectors | Grafana Alloy, Fluent Bit, Vector, OpenTelemetry Collector |
| Traces | Jaeger, Grafana Tempo, Zipkin |
| Dashboards | Grafana |
| Instrumentation standard | OpenTelemetry |
| Managed / SaaS | Datadog, New Relic, CloudWatch, Grafana Cloud |

## Observability in Kubernetes

Signals to collect, by layer:

| Layer | What to watch | Source |
|---|---|---|
| Cluster/nodes | CPU, memory, disk pressure, node `Ready` | node-exporter, kubelet/cAdvisor |
| Control plane | API server latency and errors, scheduler queue | component `/metrics` endpoints |
| Workloads | desired vs available replicas, restarts, `Ready` condition, OOMKills | kube-state-metrics |
| Containers | CPU usage vs request/limit, throttling, memory working set | cAdvisor (`container_*` metrics) |
| Applications | request rate, error rate, latency, business metrics (loans per hour) | the app's own `/metrics` |
| Events | `FailedScheduling`, `BackOff`, `Unhealthy` | `kubectl get events`, event exporters |

Kubernetes-specific practices:

- **Service discovery, not static targets.** Prometheus finds scrape targets through the
  API (ServiceMonitor/PodMonitor), so new Pods are scraped automatically.
- **Labels are the join key.** A consistent `app` / `app.kubernetes.io/name` label on Pods
  makes metrics, logs and dashboards line up.
- **Probes are health signals.** Readiness failures show up as `kube_pod_status_ready` and
  as missing endpoints. Liveness failures show up as restarts.
- **Resource requests drive everything.** HPA utilisation, scheduling and "% of request"
  dashboards all depend on them.
- **Ship logs off the node.** Container logs are rotated and deleted with the Pod, so a
  node agent (Alloy, Fluent Bit) has to forward them.
- **Alert on symptoms users feel** (error rate, latency, availability), and use
  cause-based alerts (high CPU) as warnings or info.
