# Kubernetes Storage, HPA and Probes

Author: Parth Agarwal

Three things a Deployment needs before it can be trusted with real traffic: storage that
outlives a Pod, a replica count that follows the load, and health checks that let Kubernetes
restart or bypass a sick container. All examples use a small library system (`bookshelf`,
`catalog-api`, `loan-service`, `reader-web`).

Target environment: a single-node Minikube cluster with metrics-server enabled. The
screenshots below come from Minikube (docker driver, Kubernetes v1.37) running on Colima on
an Apple Silicon Mac, so the node is arm64.

```bash
minikube start
minikube addons enable metrics-server
```

```text
Kubernetes Storage HPA and Probes/
├── volumes/        emptyDir (shared + memory), hostPath, static PV/PVC, dynamic PVC, Retain class
├── hpa/            CPU-heavy catalog-api, Service, HPA (autoscaling/v2), load generator
├── probes/         startup / liveness / readiness: healthy, broken and fixed variants
├── mini-project/   bookshelf: namespace, PVC, Deployment (init + 3 probes + resources), Service, HPA
└── screenshots/
```

---

## 1. Volumes (`volumes/`, namespace `library-storage`)

A container's own filesystem is reset every time the container restarts. A volume is
storage with a different lifetime.

| Volume | Survives | Use it for |
|---|---|---|
| `emptyDir` | container restarts, but not Pod deletion | scratch space, files shared between containers of one Pod |
| `emptyDir` with `medium: Memory` | same, stored in RAM (tmpfs) | fast cache; usage counts toward the memory limit |
| `hostPath` | Pod deletion, as long as the Pod returns to the same node | node agents; avoid for app data |
| PersistentVolume + PersistentVolumeClaim | anything that happens to Pods | databases, uploads, any data that matters |

```bash
kubectl apply -f volumes/00-namespace.yaml
```

### emptyDir shared between two containers

`emptydir-shared.yaml`: `stamper` appends a "returned book" line to `/data/returns.txt`
every 5 s, and `librarian` (nginx) serves the same directory read-only.

```bash
kubectl apply -f volumes/emptydir-shared.yaml
kubectl -n library-storage exec returns-log -c librarian -- cat /usr/share/nginx/html/returns.txt
kubectl -n library-storage delete pod returns-log      # the data goes with the Pod
```

Expect: the line count grows each time you run `cat`. After the Pod is deleted and
re-applied, the counter starts again from #1.

![emptyDir shared by two containers, reset when the Pod is re-created](screenshots/01-emptydir-shared.png)

### emptyDir in memory

```bash
kubectl apply -f volumes/emptydir-memory.yaml
kubectl -n library-storage logs search-cache
```

Expect: `df` reports `/cache` as `tmpfs` sized to the `sizeLimit`. The 10 MiB file counts
toward the Pod's memory usage, so writing more than the limit allows gets the Pod evicted.

![tmpfs emptyDir sized to sizeLimit](screenshots/02-emptydir-memory.png)

### hostPath

```bash
kubectl apply -f volumes/hostpath-pod.yaml
kubectl -n library-storage delete pod scanner-agent && kubectl apply -f volumes/hostpath-pod.yaml
minikube ssh -- cat /tmp/library-scans/scans.log
```

Expect: two lines in `scans.log`, one from each run. The file is on the node, not in
the Pod.

![hostPath file on the node keeps a line from each Pod](screenshots/03-hostpath.png)

### Static provisioning: PV + PVC

An administrator creates `pv-static.yaml` (1 Gi, `Retain`, class `manual`) by hand. The
claim in `pvc-static.yaml` asks for 500 Mi in class `manual` with a label selector, so it
can only bind to that one PV. Kubernetes binds the whole 1 Gi PV, because a PV is bound
as a single unit.

```bash
kubectl apply -f volumes/pv-static.yaml -f volumes/pvc-static.yaml
kubectl get pv catalogue-archive-pv
kubectl -n library-storage get pvc catalogue-archive        # STATUS Bound, CAPACITY 1Gi
kubectl apply -f volumes/pvc-pod.yaml
kubectl -n library-storage logs archive-writer
kubectl -n library-storage delete pod archive-writer
kubectl apply -f volumes/pvc-pod.yaml
kubectl -n library-storage logs archive-writer              # now two lines
```

![static PV bound to the claim; the claim reports the whole 1Gi](screenshots/04-pv-pvc-bound.png)

![the second Pod sees the line written by the first](screenshots/05-pv-data-survives.png)

### Dynamic provisioning and reclaim policy

`pvc-dynamic.yaml` contains two claims. Neither has a hand-made PV. `member-photos` uses
Minikube's default `standard` class (reclaim `Delete`), and `member-photos-retained` uses
`library-retain` from `storageclass-retain.yaml` (reclaim `Retain`).

```bash
kubectl get storageclass
kubectl apply -f volumes/storageclass-retain.yaml -f volumes/pvc-dynamic.yaml
kubectl get pv                                    # two new pvc-<uid> volumes appear
kubectl -n library-storage delete pvc member-photos member-photos-retained
kubectl get pv
```

Expect: the `Delete` volume disappears with its claim. The `Retain` volume stays as
`Released` and has to be deleted (and its data cleaned up) by hand. A `Released` PV is not
bound again automatically.

![two claims dynamically provisioned from two StorageClasses](screenshots/06-dynamic-provisioning.png)

![after deleting both claims: the Delete PV is gone, the Retain PV is Released](screenshots/07-reclaim-policy.png)

Access modes: `ReadWriteOnce` (one node mounts it read-write), `ReadOnlyMany`,
`ReadWriteMany` (needs shared storage such as NFS or EFS), and `ReadWriteOncePod`.

---

## 2. Horizontal Pod Autoscaler (`hpa/`, namespace `library-hpa`)

The HPA reads metrics from metrics-server and calculates:

```text
desiredReplicas = ceil(currentReplicas * currentUtilisation / targetUtilisation)
```

Utilisation is measured **against the CPU request**. Without a request the HPA shows
`<unknown>` and never scales. `catalog-api` is a busybox `httpd` serving a CGI
`/cgi-bin/search` that runs a 30 000-step shell loop, so every request costs CPU. (The
classic `registry.k8s.io/hpa-example` image is amd64-only; on an Apple Silicon Mac the
Minikube node is arm64 and that image crash-loops with `exec format error`, which also
leaves the HPA at `<unknown>`, because a crashing Pod reports no metrics.) The HPA keeps CPU at 50 % across 1–6 replicas. The `behavior` block
scales up quickly (+2 Pods per 30 s) and scales down slowly (60 s stabilisation, at most
-50 % per 30 s).

```bash
kubectl apply -f hpa/deployment.yaml -f hpa/service.yaml -f hpa/hpa.yaml
kubectl -n library-hpa get hpa catalog-api            # wait until TARGETS shows a % instead of <unknown>
kubectl apply -f hpa/load-generator.yaml
kubectl -n library-hpa get hpa catalog-api -w         # watch TARGETS and REPLICAS rise
kubectl -n library-hpa describe hpa catalog-api       # Events: "New size: N; reason: cpu resource utilization..."
kubectl -n library-hpa top pods
kubectl -n library-hpa scale deploy search-burst --replicas=0
kubectl -n library-hpa get hpa catalog-api -w         # back to 1 after the stabilisation window
```

Expect: CPU goes well above 50 % within a minute of starting the load. Replicas rise in
steps of at most two and stop at 6 (or earlier if the average drops below the target).
After the load stops, the count falls by half every 30 s until it reaches 1.

What this looked like on Minikube (Colima, arm64):

![idle baseline: 1 replica at 0 % CPU](screenshots/08-hpa-baseline.png)

`kubectl get hpa -w` (timestamps added with a `while read` loop) after the load generator
started: 1 → 3 → 5 → 6, never more than +2 per 30 s.

![HPA scaling up under load](screenshots/09-hpa-scaled-up.png)

![describe: SuccessfulRescale events and per-Pod CPU](screenshots/10-hpa-describe.png)

The `FailedGetResourceMetric` warnings in the events are from the first attempt with the
amd64-only image, when the only Pod was crash-looping and had no metrics.

The same watch, left running while `search-burst` was scaled to 0. CPU drains over the
next metrics windows, then the 60 s stabilisation window passes and the HPA halves
6 → 3 → 1:

![full kubectl get hpa -w timeline: scale up and scale down](screenshots/11-hpa-scale-up-and-down-watch.png)

![back to 1 replica, with the scale-down events](screenshots/12-hpa-scaled-down.png)

Note: on this Minikube node `kubectl top` reports `0Mi` memory for these busybox Pods;
CPU (which is what this HPA uses) is reported correctly.

---

## 3. Probes (`probes/`, namespace `library-probes`)

| Probe | Question it answers | When it fails |
|---|---|---|
| `startupProbe` | Has the app finished booting? | the container is killed once `failureThreshold × periodSeconds` is used up; liveness and readiness are paused until it passes |
| `livenessProbe` | Is the process still working? | the container is **restarted** |
| `readinessProbe` | Can it take traffic right now? | the Pod is **removed from Service endpoints**, with no restart |

```bash
kubectl apply -f probes/00-namespace.yaml
```

### Healthy baseline

```bash
kubectl apply -f probes/healthy.yaml
kubectl -n library-probes get pods -l app=reader-web        # 1/1 Running, 0 restarts
kubectl -n library-probes get endpointslices -l kubernetes.io/service-name=reader-web
```

![healthy reader-web: 2/2 ready, both addresses in the EndpointSlice](screenshots/13-probes-healthy.png)

### Broken liveness: restart loop

`liveness-broken.yaml` probes `/healthz`, which does not exist on nginx and returns 404.

```bash
kubectl apply -f probes/liveness-broken.yaml
kubectl -n library-probes get pod loan-service-liveness-broken -w
kubectl -n library-probes describe pod loan-service-liveness-broken | tail -n 15
```

Expect: `Liveness probe failed: HTTP probe failed with statuscode: 404` followed by
`Container loans failed liveness probe, will be restarted`. RESTARTS goes up about every
15–20 s, and the Pod eventually shows `CrashLoopBackOff`.

![liveness 404: restarts, then CrashLoopBackOff](screenshots/14-liveness-broken.png)

### Broken readiness: running but receiving no traffic

`readiness-broken.yaml` checks TCP 8080, but nginx listens on 80.

```bash
kubectl apply -f probes/readiness-broken.yaml
kubectl -n library-probes get pod reader-web-unready           # 0/1 Running, 0 restarts
kubectl -n library-probes get endpointslices -l kubernetes.io/service-name=reader-web-canary
```

Expect: the Pod is never restarted and never becomes Ready. The EndpointSlice lists its
address as not ready, so the Service sends it no traffic.

![readiness on the wrong port: Running 0/1, endpoint ready: false](screenshots/15-readiness-broken.png)

Fix both and compare:

```bash
kubectl -n library-probes delete pod loan-service-liveness-broken reader-web-unready
kubectl apply -f probes/fixed.yaml
kubectl -n library-probes get pods
```

![fixed probes: everything 1/1, 0 restarts, canary endpoint present](screenshots/16-probes-fixed.png)

### Startup probe: enough time vs too little

Both Pods simulate an indexer that needs about 40 s before it listens on 8080.

| File | Startup budget | Result |
|---|---|---|
| `startup-slow.yaml` | 5 s × 12 = 60 s | becomes Ready after about 40 s, 0 restarts |
| `startup-too-short.yaml` | 5 s × 4 = 20 s | killed before it ever listens; restarts forever, never Ready |

```bash
kubectl apply -f probes/startup-slow.yaml -f probes/startup-too-short.yaml
kubectl -n library-probes get pods -l '!app' -w
kubectl -n library-probes describe pod index-builder-too-short | grep -E "Startup|Unhealthy|Killing"
```

![startup probe: 60 s budget becomes Ready at ~45 s, 20 s budget restarts forever](screenshots/17-startup-probe.png)

Observed: the too-short Pod restarts about every 50 s rather than every 20 s. The probe
gives up after 20 s, but the container's PID 1 is `sh` busy in `sleep`, which ignores
SIGTERM, so the kubelet waits the default 30 s grace period before it sends SIGKILL.

Rule of thumb: set the startup budget above the slowest boot you have seen, and keep
liveness strict. Without a startup probe you would have to give liveness a long
`initialDelaySeconds`, and a real hang would then take longer to detect.

---

## 4. Mini project: production-ready `bookshelf` (`mini-project/`, namespace `library`)

All the parts of this lab in one app:

| File | What it adds |
|---|---|
| `00-namespace.yaml` | dedicated `library` namespace (the `00-` prefix makes `kubectl apply -f mini-project/` create it before the namespaced objects) |
| `pvc.yaml` | 256 Mi dynamically provisioned claim for the page and a boot log |
| `deployment.yaml` | init container that seeds the page once and appends to `boot.log`; nginx with requests/limits; startup, liveness and readiness probes; `maxUnavailable: 0` rolling updates |
| `service.yaml` | NodePort 30881 |
| `hpa.yaml` | 2–5 replicas on CPU 60 % **or** memory 80 % |

```bash
kubectl apply -f mini-project/
kubectl -n library get pvc,deploy,pods,svc,hpa
curl "$(minikube service bookshelf -n library --url)"
# with the docker driver on macOS, `minikube service --url` keeps a tunnel open in the
# foreground; a port-forward is simpler:
kubectl -n library port-forward svc/bookshelf 18881:80 &
curl http://localhost:18881/

# persistence: delete every Pod, then check the page and boot log survived
kubectl -n library delete pod -l app=bookshelf
kubectl -n library rollout status deploy/bookshelf
kubectl -n library exec deploy/bookshelf -- cat /usr/share/nginx/html/boot.log

# health
kubectl -n library describe pod -l app=bookshelf | grep -E "Liveness|Readiness|Startup"

# scaling: generate load and watch the HPA
kubectl -n library run shelf-load --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://bookshelf >/dev/null; done'
kubectl -n library get hpa bookshelf -w
kubectl -n library delete pod shelf-load
```

Expect: the "Seeded at" time on the page stays the same after the Pods are replaced, and
`boot.log` gains one line for every Pod that has ever started. nginx needs very little
CPU per request, so a single load Pod may only push it slightly past 60 %. Run two or
three load Pods if the HPA does not react.

![bookshelf mini project applied](screenshots/18-mini-deploy.png)

![bookshelf page in the browser (via port-forward)](screenshots/19-mini-browser.png)

![every Pod deleted: same Seeded-at time, boot.log keeps growing](screenshots/20-mini-persistence.png)

![init container completed, three probes configured](screenshots/21-mini-health.png)

With three load Pods running the HPA went 2 → 5 (CPU 124 % of the 50m request), and
about 90 s after they were deleted it returned to 2:

![bookshelf HPA timeline](screenshots/22-mini-hpa-watch.png)

Note: the claim is `ReadWriteOnce`. On a single-node cluster every replica mounts it from
the same node, so this works. On a multi-node cluster the replicas would need
`ReadWriteMany` storage, or each one its own volume through a StatefulSet.

---

## Cleanup

```bash
kubectl delete ns library-storage library-hpa library-probes library
kubectl delete pv catalogue-archive-pv
kubectl get pv            # delete any Released PVs left by the Retain class
minikube ssh -- sudo rm -rf /tmp/hostpath-provisioner/library-storage /tmp/library-scans /tmp/catalogue-archive
kubectl delete storageclass library-retain
```

## Cheat sheet

```bash
kubectl get pv,pvc -A
kubectl get storageclass
kubectl describe pvc NAME                 # why is it Pending?
kubectl get hpa -w ; kubectl top pods
kubectl describe pod NAME | grep -A2 -E "Liveness|Readiness|Startup"
kubectl get endpointslices -l kubernetes.io/service-name=SVC
```
