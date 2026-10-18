# GitOps with Argo CD

## What GitOps is

GitOps means running deployments from Git. The desired state of the cluster is kept as
declarative files in a Git repository, and an agent inside the cluster keeps making the
live state match those files. Nobody runs `kubectl apply` against production. You change
the repository, and the agent rolls the change out.

Four principles (OpenGitOps):

1. **Declarative**: the whole system is described as data (YAML manifests, Helm values,
   Kustomize overlays), not as a list of commands.
2. **Versioned and immutable**: that description lives in Git, so every change has an
   author, a review (pull request), a timestamp and can be reverted.
3. **Pulled automatically**: an agent in the cluster fetches the desired state. CI never
   needs cluster credentials.
4. **Continuously reconciled**: the agent keeps comparing desired and live state and
   fixes any difference (*drift*).

## Push vs pull deployment

| | Push (classic CI/CD) | Pull (GitOps) |
|---|---|---|
| Who applies | CI job runs `kubectl`/`helm` | agent in the cluster (Argo CD, Flux) |
| Credentials | CI holds cluster admin credentials | cluster only needs read access to Git |
| Drift | manual changes stay until the next deploy | detected and (optionally) reverted within minutes |
| Audit / rollback | spread across CI logs | `git log` / `git revert` |
| Multi-cluster | CI must reach every cluster | each cluster pulls on its own |

CI still has a job in GitOps: it tests, builds and pushes the image, then commits the new
tag to the config repo (or opens a PR). It just never talks to the cluster.

## Workflow

```text
developer ── PR ──► Git (app/ manifests) ◄── polls every 60s ── Argo CD (in cluster)
                         │                                         │
                    review + merge                        diff desired vs live
                                                                   │
                                                     sync: apply / prune / self-heal
                                                                   ▼
                                                     namespace library-gitops
```

Argo CD statuses: **Sync** (`Synced` / `OutOfSync`: does live match Git?) and **Health**
(`Healthy` / `Progressing` / `Degraded`: are the resources actually working?).

## Files

| File | Purpose |
|---|---|
| `argocd-values.yaml` | small, non-HA Argo CD (no Dex, no notifications, plain HTTP behind port-forward, 60 s polling) |
| `gitops-repo/app/` | the desired state: Namespace, `reader-web` Deployment (2 × `nginx:1.26-alpine`), Service |
| `gitops-repo/argocd/application.yaml` | Application: watches `app/` on branch `gitops-demo`, automated sync with `prune` + `selfHeal`, `CreateNamespace=true` |

The Application points at this DevOps repository on GitHub. Replace `YOUR_GITHUB_USER`
before applying it. A public repo needs no credentials. For a private repo, add it with
`argocd repo add` or a repository Secret. Demo commits go to a `gitops-demo` branch so that
`main` stays clean.

## Hands-on (needs a cluster and a GitHub remote)

### 0. Install Argo CD and register the app

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace -f gitops/argocd-values.yaml --wait

git switch -c gitops-demo && git push -u origin gitops-demo
sed -i.bak 's/YOUR_GITHUB_USER/<your-user>/' gitops/gitops-repo/argocd/application.yaml
kubectl apply -f gitops/gitops-repo/argocd/application.yaml

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80      # UI at http://localhost:8080, user admin
```

### 1. Initial sync

```bash
kubectl -n argocd get application reader-web
kubectl -n library-gitops get deploy,pods,svc
```

Expect: `Synced` / `Healthy`. The namespace, Deployment and Service exist even though you
never ran `kubectl apply` on them.

### 2. A commit is a deployment

Edit `gitops-repo/app/deployment.yaml`: `replicas: 3` and `image: nginx:1.27-alpine`.

```bash
git commit -am "reader-web: 3 replicas, nginx 1.27" && git push
kubectl -n library-gitops get pods -w
kubectl -n argocd get application reader-web -o jsonpath='{.status.sync.revision}{"\n"}'
```

Expect: within about one polling interval the app goes `OutOfSync` → `Synced`, three Pods
run the new image, and the synced revision equals your commit SHA. Click **Refresh** in the
UI to skip the wait.

### 3. Drift is self-healed

```bash
kubectl -n library-gitops scale deploy reader-web --replicas=1
kubectl -n library-gitops delete svc reader-web
kubectl -n library-gitops get deploy,svc -w
```

Expect: Argo CD notices the drift and puts back 3 replicas and the Service within seconds.
To make a change stick, you have to commit it.

### 4. Rollback is `git revert`

```bash
git revert --no-edit HEAD && git push
kubectl -n library-gitops get pods -w
```

Expect: back to 2 × `nginx:1.26-alpine`. The rollback is a new commit, so the history shows
who rolled back and when. (`kubectl rollout undo` would be reverted by self-heal, because
Git still says otherwise.)

### Cleanup

```bash
kubectl delete -f gitops/gitops-repo/argocd/application.yaml   # finalizer removes library-gitops objects
helm uninstall argocd -n argocd && kubectl delete ns argocd library-gitops --ignore-not-found
git switch main && git push origin --delete gitops-demo
```

## Argo CD vs Flux (short)

Both are CNCF-graduated pull-based GitOps controllers. Argo CD has a rich web UI, an
`Application` CRD and app-of-apps / ApplicationSet for many apps or clusters. Flux is a set
of smaller controllers (`GitRepository`, `Kustomization`, `HelmRelease`), driven mostly from
the CLI, with built-in image-update automation.
