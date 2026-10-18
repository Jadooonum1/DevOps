# Kubernetes Ingress, ConfigMaps and Secrets

**Goal:** move configuration out of the container image (ConfigMap), keep credentials in a
separate object (Secret), inject both into an app, and put a single HTTP entry point
(Ingress) in front of two Services, routing by path.

Author: Parth Agarwal · Cluster: Minikube, Docker driver · Namespace: `library`

## Concepts in brief

| Object | Purpose |
|---|---|
| **ConfigMap** | Non-sensitive key/value settings or whole config files, kept outside the image |
| **Secret** | Sensitive values. Stored base64-encoded (encoding, not encryption); access is controlled separately with RBAC |
| **Ingress** | Layer-7 routing rules (host + path → Service), one entry point for many Services |
| **Ingress controller** | The reverse proxy (ingress-nginx here) that watches Ingress objects and actually serves the traffic |

What gets built:

```text
                     Host: library.local
 curl / browser ──► ingress-nginx controller
                        │                     │
                  /api/... (prefix stripped)  / (everything else)
                        ▼                     ▼
              Service catalog-api       Service reader-web      (ClusterIP)
                        ▼                     ▼
              2 x nginx JSON API        2 x nginx static page
                ▲            ▲
       ConfigMap catalog-config   Secret catalog-db-secret
```

`catalog-api` is plain `nginx:1.27-alpine`. The official image runs `envsubst` over
`/etc/nginx/templates/*.template` at start-up, so mounting a template from a ConfigMap and
injecting env vars is enough to get a small JSON API that reports its own configuration.

## Files

| File | Contents |
|---|---|
| [`manifests/00-namespace.yaml`](manifests/00-namespace.yaml) | `library` namespace |
| [`manifests/01-configmap.yaml`](manifests/01-configmap.yaml) | `catalog-config`: `LIBRARY_NAME`, `MAX_LOANS_PER_MEMBER`, `LOAN_PERIOD_DAYS`, `LOG_LEVEL` |
| [`manifests/02-secret.yaml`](manifests/02-secret.yaml) | `catalog-db-secret`: `DB_USER`, `DB_PASSWORD` (demo values, via `stringData`) |
| [`manifests/03-catalog-api.yaml`](manifests/03-catalog-api.yaml) | nginx template ConfigMap, Deployment (envFrom ConfigMap + secretKeyRef), Service |
| [`manifests/03-reader-web.yaml`](manifests/03-reader-web.yaml) | HTML ConfigMap, Deployment, Service |
| [`manifests/04-ingress.yaml`](manifests/04-ingress.yaml) | Ingress `library-ingress` for host `library.local` |

## 0. Ingress controller

An Ingress object is only data until a controller acts on it. Minikube ships ingress-nginx as
an addon:

```bash
minikube start --driver=docker
minikube addons enable ingress
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl get pods -n ingress-nginx
kubectl get ingressclass
```

**Expect:** one `ingress-nginx-controller-*` Pod Running, and an IngressClass named `nginx`.
That name is what `ingressClassName: nginx` in the Ingress refers to.

## 1. ConfigMap

```bash
cd manifests
kubectl apply -f 00-namespace.yaml -f 01-configmap.yaml
kubectl -n library get configmap catalog-config
kubectl -n library describe configmap catalog-config

# imperative alternative, handy for experiments
kubectl -n library create configmap branch-config \
  --from-literal=BRANCH=riverside --from-literal=OPEN_SUNDAY=false --dry-run=client -o yaml
```

**What to look for:** the four keys under `Data`, in plain text. The `--dry-run` command just
prints YAML, which is a quick way to generate a ConfigMap file. All ConfigMap values are
strings, which is why `"5"` and `"21"` are quoted in the manifest.

## 2. Secret

```bash
kubectl apply -f 02-secret.yaml
kubectl -n library get secret catalog-db-secret
kubectl -n library describe secret catalog-db-secret          # sizes only, no values
kubectl -n library get secret catalog-db-secret -o jsonpath='{.data.DB_USER}'; echo
kubectl -n library get secret catalog-db-secret -o jsonpath='{.data.DB_USER}' | base64 -d; echo
```

**What to look for:** `describe` shows only byte counts, but `-o jsonpath` shows the
base64 string, and `base64 -d` turns it straight back into `catalog_ro`. Anyone who can
`get` a Secret can read it. Protection comes from RBAC, from enabling encryption at rest for
etcd, and from not committing real values to Git. The manifest here contains demo values
only, and says so.

## 3. Inject both into the apps

```bash
kubectl apply -f 03-catalog-api.yaml -f 03-reader-web.yaml
kubectl -n library rollout status deploy/catalog-api
kubectl -n library rollout status deploy/reader-web
kubectl -n library get deploy,pods,svc -o wide

kubectl -n library exec deploy/catalog-api -- printenv LIBRARY_NAME MAX_LOANS_PER_MEMBER LOAN_PERIOD_DAYS DB_USER
kubectl -n library exec deploy/catalog-api -- sh -c 'test -n "$DB_PASSWORD" && echo "DB_PASSWORD is set (${#DB_PASSWORD} chars)"'
kubectl -n library exec deploy/catalog-api -- cat /etc/nginx/conf.d/default.conf | head -8
```

**What to look for:** the ConfigMap keys appear as env vars with the same names (`envFrom`),
and the two Secret keys appear because each was mapped with `secretKeyRef`. The password is
checked for presence and length rather than printed. The rendered `default.conf` shows the
template with the values filled in.

## 4. Ingress

```bash
kubectl apply -f 04-ingress.yaml
kubectl -n library get ingress library-ingress -w      # wait until ADDRESS is filled, then Ctrl-C
kubectl -n library describe ingress library-ingress
```

With the Docker driver on macOS the node IP is not reachable from the host, so reach the
controller through a port-forward (or `minikube tunnel` + `127.0.0.1`):

```bash
# terminal 2
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80

# terminal 1
curl -s -H 'Host: library.local' http://localhost:8080/ | grep '<title>'
curl -s -H 'Host: library.local' http://localhost:8080/api/
curl -s -H 'Host: library.local' http://localhost:8080/api/books
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/            # no Host header
for i in 1 2 3 4; do curl -s -H 'Host: library.local' http://localhost:8080/api/ | grep -o '"pod":"[^"]*"'; done
```

For a browser, add `127.0.0.1 library.local` to `/etc/hosts` and open
`http://library.local:8080/`.

**What to look for:**

- `describe ingress` lists both rules with their backend Pod IPs. If a backend shows
  `<error: services "..." not found>`, the Service name is wrong.
- `/` returns the Reader Web page; `/api/` returns the catalog-api JSON with the ConfigMap
  values and `"dbUser":"catalog_ro"`; `/api/books` returns the book list. The `/api` prefix
  is stripped by `rewrite-target: /$2` before the request reaches catalog-api, which only
  knows `/`, `/books` and `/healthz`.
- Without the `Host: library.local` header the request does not match any rule and the
  controller returns `404`.
- The `"pod"` field changes between requests: the controller load-balances across both
  catalog-api replicas.

## 5. Changing configuration

Env vars are read once at container start, so editing a ConfigMap does not change running
Pods that consume it through `envFrom`:

```bash
kubectl -n library patch configmap catalog-config -p '{"data":{"MAX_LOANS_PER_MEMBER":"8"}}'
curl -s -H 'Host: library.local' http://localhost:8080/api/       # still maxLoans 5
kubectl -n library rollout restart deploy/catalog-api
kubectl -n library rollout status deploy/catalog-api
curl -s -H 'Host: library.local' http://localhost:8080/api/       # now maxLoans 8
```

## Cleanup

```bash
kubectl delete -f 04-ingress.yaml -f 03-reader-web.yaml -f 03-catalog-api.yaml -f 02-secret.yaml -f 01-configmap.yaml
# minikube addons disable ingress   # if you do not need it for the Advanced exercise
```

## Screenshots to capture

Save into [`screenshots/`](screenshots):

1. `ingress-controller.png` - controller Pod and `kubectl get ingressclass`
2. `configmap.png` - `describe configmap catalog-config`
3. `secret.png` - `describe secret` (sizes only) next to the `base64 -d` result
4. `apps-env.png` - `printenv` output from catalog-api and the DB_PASSWORD presence check
5. `ingress-describe.png` - `get ingress` with ADDRESS and `describe ingress`
6. `ingress-routing.png` - the curls to `/`, `/api/`, `/api/books` and the 404 without Host
7. `configmap-restart.png` - maxLoans before and after the rollout restart
