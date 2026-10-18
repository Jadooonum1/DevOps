# Monitoring, Observability and GitOps

Author: Parth Agarwal

This lab gives the library system a monitoring stack and a GitOps workflow:

- **Metrics**: Prometheus (via kube-prometheus-stack) scrapes the cluster and the
  `catalog-api` sample app. Grafana shows dashboards, and Alertmanager receives alerts
  from custom PrometheusRules.
- **Logs**: Grafana Alloy (a DaemonSet) tails container logs on the node and pushes them
  to Loki. Grafana queries Loki with LogQL.
- **GitOps**: Argo CD keeps a namespace in sync with a folder in Git.

Target environment: Minikube with about 4 CPUs and 8 GB
(`minikube start --cpus=4 --memory=8g`) and the metrics-server addon.

```text
Monitoring Observability and GitOps/
├── monitoring/
│   ├── helm-values/   kube-prometheus-stack, loki, alloy values
│   ├── alerts/        library-rules.yaml (PrometheusRule: 1 recording + 5 alerting rules)
│   └── sample-app/    namespace library-obs: catalog-api (+ServiceMonitor), traffic, CPU hog, crash loop, never-ready Pod
├── observability/     README.md: monitoring vs observability, metrics/logs/traces, tools, Kubernetes
├── gitops/            README.md, argocd-values.yaml, gitops-repo/{app,argocd}
└── screenshots/
```

## 0. Install the stack

```bash
minikube addons enable metrics-server
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  -f monitoring/helm-values/kube-prometheus-stack-values.yaml --wait
helm install loki grafana/loki -n logging --create-namespace -f monitoring/helm-values/loki-values.yaml
helm install alloy grafana/alloy -n logging -f monitoring/helm-values/alloy-values.yaml

kubectl apply -f monitoring/sample-app/ -f monitoring/alerts/
kubectl get pods -n monitoring; kubectl get pods -n logging; kubectl get pods -n library-obs
```

UIs (one terminal each):

```bash
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
kubectl -n monitoring port-forward svc/kps-grafana 3000:80          # admin / library-lab-only
```

Main value choices: Minikube's control-plane components (etcd, scheduler,
controller-manager, kube-proxy) are not scraped, because they listen on localhost inside
the node and would otherwise show up as permanently down. The `*SelectorNilUsesHelmValues:
false` settings let Prometheus pick up ServiceMonitors and rules from any namespace. Loki
is added to Grafana as a datasource. Alertmanager sends `team="library"` alerts to their
own placeholder receiver.

## 1. Metrics

**Targets.** In Prometheus, *Status → Targets* should list `serviceMonitor/library-obs/catalog-api/0`
with 2 endpoints `UP`, as well as node-exporter, kube-state-metrics, kubelet/cAdvisor and
the API server.

**PromQL** queries to try (Graph tab):

```promql
# request rate per status code (recording rule from library-rules.yaml)
library:catalog_api_requests:rate1m

# share of failed requests, should be about 0.2 because reader-traffic sends every 5th request to /status/500
sum(rate(http_requests_total{service="catalog-api",status=~"5.."}[2m]))
  / sum(rate(http_requests_total{service="catalog-api"}[2m]))

# p95 latency
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{service="catalog-api"}[5m])))

# CPU (cores) and memory per Pod in the namespace
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="library-obs", container!=""}[5m]))
sum by (pod) (container_memory_working_set_bytes{namespace="library-obs", container!=""})

# restarts and readiness from kube-state-metrics
kube_pod_container_status_restarts_total{namespace="library-obs"}
kube_pod_status_ready{namespace="library-obs", condition="false"} == 1
```

## 2. Logs

`kubectl logs` shows a single container, only while that Pod exists, and has no search
across Pods:

```bash
kubectl -n library-obs logs deploy/reader-traffic --tail=5
kubectl -n library-obs logs deploy/fine-sync --previous
```

In Grafana go to *Explore → Loki*. Example LogQL:

```logql
{namespace="library-obs"}
{namespace="library-obs", app="fine-sync"} |= "ERROR"
{namespace="library-obs", app="reader-traffic"} |= "status=500"
sum by (app) (count_over_time({namespace="library-obs"} |= "ERROR" [5m]))
sum(rate({app="reader-traffic"} |= "status=500" [1m]))
```

Expect: the `ERROR payments gateway unreachable` lines from every past `fine-sync` container,
including ones that `kubectl logs --previous` can no longer show. The count of
`status=500` lines per minute should match the Prometheus 5xx rate.

## 3. Alerts

`monitoring/alerts/library-rules.yaml` (checked with `promtool check rules`: 6 rules):

| Alert | Fires because of | Expression idea |
|---|---|---|
| `CatalogApiHighErrorRate` | `reader-traffic` (20 % 500s) | 5xx / all > 5 % for 2 m |
| `CatalogApiDown` | scale `catalog-api` to 0 to test it | `absent(up{service="catalog-api"} == 1)` |
| `LibraryPodRestarting` | `fine-sync` exits every ~20 s | restarts increase > 2 in 10 m |
| `LibraryPodNotReady` | `reader-web-canary` probes `/ready` (404) | `kube_pod_status_ready{condition="false"}` for 3 m |
| `LibraryHighCpu` | `isbn-reindex` busy loop | CPU usage / CPU limit > 90 % for 5 m |

```bash
kubectl -n library-obs get prometheusrules
# Prometheus → Alerts: rules move Inactive → Pending → Firing
# Alertmanager UI: firing alerts grouped by alertname+namespace, receiver library-team
kubectl -n library-obs scale deploy catalog-api --replicas=0   # CatalogApiDown after ~1 min
kubectl -n library-obs scale deploy catalog-api --replicas=2
```

## 4. CPU and memory utilisation

```bash
kubectl top nodes
kubectl top pods -n library-obs --sort-by=cpu
```

`kubectl top` gives a single snapshot from metrics-server. For history, use the Grafana
dashboards that ship with the chart: *Kubernetes / Compute Resources / Namespace (Pods)*
for `library-obs` (usage vs requests and limits per Pod), and *Node Exporter / Nodes*.
Expect `isbn-reindex` at its 200m CPU limit (about 200 % of its 100m request), and
`catalog-api` well below its request.

## 5. Application health

```bash
kubectl -n library-obs get deploy,pods
kubectl -n library-obs get endpointslices
kubectl -n library-obs describe pod -l app=reader-web-canary | grep -A3 Readiness
kubectl -n library-obs port-forward svc/catalog-api 9898:9898 & curl -s localhost:9898/healthz
```

Expect: `catalog-api` 2/2 Ready with both IPs in its EndpointSlice. `reader-web-canary`
stays 0/1 with a 404 readiness failure. `fine-sync` shows a growing restart count. These
are the same facts that the alerts above turn into notifications.

## 6. Observability concepts

See [`observability/README.md`](observability/README.md): monitoring vs observability, the
three pillars and how they connect, common tools, and what to observe in Kubernetes.

## 7. GitOps with Argo CD

See [`gitops/README.md`](gitops/README.md): concepts (declarative, versioned, pulled,
reconciled; push vs pull), then installing Argo CD and walking through initial sync,
deploy-by-commit, drift self-heal and rollback by `git revert`.

## Validated locally (no cluster)

- `kubeconform -strict` on `monitoring/sample-app`, `monitoring/alerts` and
  `gitops/gitops-repo` (13 resources, ServiceMonitor/PrometheusRule/Application checked
  against the datreeio CRDs-catalog schemas): all valid.
- `promtool check rules` (prom/prometheus v3.5.0) on the rule groups: 6 rules, SUCCESS.
- `helm template` of kube-prometheus-stack, loki, alloy and argo-cd with these values
  files rendered without errors, and the output passed kubeconform (CRD kinds skipped).
- `alloy fmt` (grafana/alloy v1.10.0) accepted the Alloy config.
- podinfo 6.7.1 was run locally: `/status/500` returns 500, and `/metrics` exposes
  `http_requests_total{status=...}` and `http_request_duration_seconds_*`, which the rules
  and queries above use.

## Cleanup

```bash
kubectl delete -f monitoring/sample-app/ -f monitoring/alerts/
helm uninstall alloy loki -n logging
helm uninstall kps -n monitoring
kubectl delete ns logging monitoring library-obs
# kube-prometheus-stack CRDs stay behind: kubectl get crd | grep monitoring.coreos.com
```

## Screenshots to capture (`screenshots/`)

`monitoring-stack.png` (pods in monitoring/logging), `prometheus-targets.png`,
`prometheus-promql-rate.png`, `prometheus-cpu-table.png`, `kubectl-logs.png`,
`grafana-explore-loki.png`, `prometheus-alerts.png`, `alertmanager-alerts.png`,
`kubectl-top.png`, `grafana-namespace-cpu-mem.png`, `grafana-node.png`, `app-health.png`,
`argocd-initial.png`, `gitops-commit-sync.png`, `gitops-selfheal.png`, `gitops-rollback.png`.

## Cheat sheet

```bash
kubectl get servicemonitors,prometheusrules -A
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
kubectl top pods -A --sort-by=memory
kubectl -n argocd get applications
kubectl -n argocd get application NAME -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```
