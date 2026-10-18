# Kubernetes Troubleshooting

Author: Parth Agarwal

Practice in finding out *why* something on a cluster is broken. Every fault here is planted
on purpose in a small library system (catalogue sync, loans, reader web front end), so each
one can be reproduced, diagnosed and fixed. Target environment: a single-node Minikube
cluster. Use `minikube start --cni=calico` if you want the NetworkPolicy part of issue 08
to be enforced.

The same loop is used for every problem:

1. **`get`**: what state is it in? (`Pending`, `CrashLoopBackOff`, `0/1 Ready`, no endpoints)
2. **`describe` / events**: what did Kubernetes try, and what failed? (scheduling, image pull, mount, probes)
3. **`logs` / `logs --previous`**: what did the process print before it died?
4. **`exec`**: look from inside the container (files, env, DNS, listening ports)
5. Change **one** thing, re-apply, and go back to step 1

```text
Kubernetes Troubleshooting/
├── commands/          circulation-desk.yaml: healthy workload for practising the commands
├── issues/            11 cases: broken.yaml, fixed.yaml and README.md in each
├── triage-gauntlet/   5 broken Pods + triage.sh (deploy / report / fix / clean)
├── mini-project/      healthy app + Pod with stacked faults + selector challenge
└── screenshots/
```

---

## 1. Core commands (`commands/`)

```bash
kubectl create namespace lib-cmds
kubectl -n lib-cmds apply -f commands/circulation-desk.yaml
```

| Command | Use it to |
|---|---|
| `kubectl -n lib-cmds get pods -o wide --show-labels` | see status, restarts, node, Pod IP and labels at a glance |
| `kubectl -n lib-cmds describe pod <pod>` | see conditions, container state, last state, exit code and **Events** |
| `kubectl -n lib-cmds logs deploy/circulation-desk -f --tail=20` | follow the app output (`--previous` for the last crashed container, `-c` to pick a container) |
| `kubectl -n lib-cmds logs -l app=circulation-desk --prefix` | read the logs of every replica at once |
| `kubectl -n lib-cmds exec -it deploy/circulation-desk -- sh` | get a shell inside: `env`, `cat /etc/resolv.conf`, `wget -qO- localhost:8080`, `netstat -tln` |
| `kubectl -n lib-cmds get events --sort-by=.lastTimestamp` | see the namespace timeline (events are kept for about 1 h only) |
| `kubectl -n lib-cmds top pods` | check current CPU and memory use (needs metrics-server) |
| `kubectl explain pod.spec.containers.readinessProbe` | read field docs offline, useful for "is this field valid?" questions |
| `kubectl -n lib-cmds rollout restart deploy/circulation-desk` | replace every Pod with a new one (for example after a ConfigMap change) |
| `kubectl -n lib-cmds rollout status / history / undo deploy/circulation-desk` | follow or revert a rollout |
| `kubectl -n lib-cmds debug -it <pod> --image=busybox:1.36 --target=desk` | attach an ephemeral debug container that shares the Pod's process namespace |

What to look for: the checkout counter in the logs restarts at #1 after a `rollout restart`
(the Pods are new), the Pod names and IPs change, and `rollout history` shows a new revision.

Screenshots: `cmd-get-describe.png`, `cmd-logs-exec.png`, `cmd-events-top-explain.png`,
`cmd-rollout-restart.png`.

---

## 2. Eleven common issues (`issues/`)

Each folder has its own README with the reproduction steps, the diagnosis commands, what to
look for and the fix. To see everything at once:

```bash
kubectl create namespace lib-issues
for d in issues/*/; do kubectl -n lib-issues apply -f "$d/broken.yaml"; done
kubectl -n lib-issues get pods,svc
```

| # | Issue | Status you see | Planted cause | Where the answer is |
|---|---|---|---|---|
| [01](issues/01-crashloopbackoff) | CrashLoopBackOff | `Error` → `CrashLoopBackOff` | required env var missing, exit 1 | `logs --previous` |
| [02](issues/02-imagepullbackoff) | ImagePullBackOff | `ImagePullBackOff` | tag typo `2.4-alpinee` | event: not found |
| [03](issues/03-errimagepull) | ErrImagePull | `ErrImagePull` ⇄ backoff | registry host `.invalid` | event: no such host |
| [04](issues/04-pending) | Pending | `Pending`, node `<none>` | requests 64 CPUs | event: Insufficient cpu |
| [05](issues/05-containercreating) | ContainerCreating | stuck `ContainerCreating` | Secret volume missing | event: FailedMount |
| [06](issues/06-service-connectivity) | Service connectivity | Pods Ready, connection refused | `targetPort` 8080 vs 80 | EndpointSlice port |
| [07](issues/07-dns) | DNS | lookups time out | `dnsPolicy: None` + dead nameserver | `/etc/resolv.conf` |
| [08](issues/08-pod-networking) | Pod networking | refused, then timed out | bind 127.0.0.1; deny-all NetworkPolicy | `netstat`, `get netpol` |
| [09](issues/09-config-bad-configmap-key) | Bad ConfigMap key | `CreateContainerConfigError` | `BRANCH_COD` vs `BRANCH_CODE` | event |
| [10](issues/10-config-wrong-command) | Wrong command | `RunContainerError`, exit 128 | `ngnix` | `lastState.terminated.message` |
| [11](issues/11-oomkilled) | OOMKilled | `OOMKilled`, exit 137 | 150 MiB in a 64 Mi limit | `lastState.terminated.reason` |

Patterns worth remembering:

- **Before vs after the process starts.** 02, 03, 04, 05 and 09 fail before any container
  exists, so `logs` is empty and the **events** have the answer. 01, 10 and 11 fail after
  the container is created, so the **exit code** and `logs --previous` explain them.
- **Exit codes.** `1`/`2`: the app decided to quit. `128`: the runtime could not exec the
  command. `137`: SIGKILL, almost always the OOM killer.
- **Refused vs timed out.** *Refused* means the host is reachable but nothing is listening
  on that IP:port (wrong `targetPort`, loopback bind). *Timed out* means packets are being
  dropped (NetworkPolicy, firewall, a dead DNS server).
- **Empty EndpointSlice** means a selector or readiness problem. **Endpoints present but
  the call fails** means a port or bind problem.

Screenshots: `NN-<issue>-broken.png` and `NN-<issue>-fixed.png` for each issue, plus
`overview-broken.png`.

---

## 3. Triage gauntlet (`triage-gauntlet/`)

Five broken Pods are deployed together. `triage.sh` prints a one-screen report: the status
of each Pod (the last termination reason takes priority, so an OOMKilled Pod caught between
restarts is still reported as OOMKilled), the restart count and last exit code, the newest
Warning event, the last log line, and a hint about where to look next.

```bash
cd triage-gauntlet
./triage.sh deploy            # apply all broken.yaml, wait 45s, print the report
./triage.sh report            # re-print the report at any time
./triage.sh fix               # replace every Pod with its fixed.yaml and report again
./triage.sh clean             # delete the lib-gauntlet namespace
```

| Pod | Report should point to | Fix |
|---|---|---|
| `fine-calculator` | `CrashLoopBackOff`, exit 2, log `/config/fines.conf not found` | ConfigMap mounted at `/config` |
| `barcode-printer` | `ErrImagePull`/`ImagePullBackOff`, repository does not exist | public `busybox` image |
| `rare-books-vault` | `Pending`, node affinity/selector mismatch | drop the `nodeSelector` (or label a node) |
| `overdue-notifier` | **`Running`**, but the log says `cannot resolve loan-servce` | create the `loan-service` Service and fix the name |
| `report-builder` | `OOMKilled`, exit 137 | memory limit 32 Mi → 192 Mi |

`overdue-notifier` is the reason the script always prints the last log line: its status
is green and it never restarts, so a triage that stops at `kubectl get pods` misses it.

Screenshots: `gauntlet-triage.png`, `gauntlet-fixed.png`.

---

## 4. Mini project

See [`mini-project/README.md`](mini-project/README.md): a healthy `reader-web` baseline,
an `isbn-indexer` Pod with two stacked faults, and a Service selector that matches no Pods.

---

## Symptom → first command

| Symptom | First command | Usual causes |
|---|---|---|
| `Pending` | `describe pod` → Events | requests too large, selector/affinity, taints, unbound PVC |
| `ImagePullBackOff` / `ErrImagePull` | `describe pod` → Events | tag typo, private registry without `imagePullSecrets`, DNS/proxy |
| `ContainerCreating` (stuck) | `describe pod` → Events | missing Secret/ConfigMap volume, PVC, CNI |
| `CreateContainerConfigError` | `describe pod` → Events | missing ConfigMap/Secret or key in `env` |
| `CrashLoopBackOff` | `logs --previous`, `describe` (exit code) | app config error, bad command, failing liveness probe, OOM |
| `Running` but `0/1` | `describe pod` → readiness probe events | wrong probe path/port, dependency down |
| Service does not answer | `get endpointslices` | selector mismatch, no Ready Pods, wrong `targetPort` |
| Name does not resolve | `exec ... cat /etc/resolv.conf`, `nslookup` | wrong name or namespace, `dnsPolicy`, CoreDNS down |

## Cleanup

```bash
kubectl delete namespace lib-cmds lib-issues lib-gauntlet lib-mini --ignore-not-found
```
