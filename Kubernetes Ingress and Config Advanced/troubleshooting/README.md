# Troubleshooting ConfigMaps, Secrets and Ingress

Five mistakes that are easy to make and do not always look like what they are. Each folder
has a broken and a fixed version. All broken files are valid Kubernetes objects (they pass
schema validation); the faults only show at runtime, which is what makes them realistic.

**Prerequisites:** the main [README](../README.md) section 3 is running (ingress addon
enabled, `catalog-api` and `reader-web` deployed in namespace `library`), the current
namespace is `library`, and the controller is port-forwarded:

```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 8443:443
```

Run the commands from this `troubleshooting/` folder.

## 1. Secret with a trailing newline

[`01-secret-newline/`](01-secret-newline): `loan-service` (nginx) answers `/loans` only when
the `X-Api-Key` header equals its `API_KEY` env var exactly. The broken Secret was encoded
with `echo 'lib-7c1e' | base64`, i.e. without `-n`.

```bash
kubectl apply -f 01-secret-newline/secret-broken.yaml -f 01-secret-newline/loan-service.yaml
kubectl rollout status deploy/loan-service
kubectl port-forward svc/loan-service 9000:80 &
curl -s -w ' %{http_code}\n' -H 'X-Api-Key: lib-7c1e' localhost:9000/loans

# diagnose
kubectl get secret loan-service-api-key -o jsonpath='{.data.API_KEY}' | base64 -d | od -c
kubectl exec deploy/loan-service -- sh -c 'printf %s "$API_KEY" | od -c'

# fix: replace the Secret, then restart so the env var is read again
kubectl apply -f 01-secret-newline/secret-fixed.yaml
kubectl rollout restart deploy/loan-service && kubectl rollout status deploy/loan-service
kill %1; kubectl port-forward svc/loan-service 9000:80 &
curl -s -w ' %{http_code}\n' -H 'X-Api-Key: lib-7c1e' localhost:9000/loans
```

- **Symptom:** `401 {"error":"invalid api key"}` even though the client sends the right
  key, and `base64 -d` *looks* like exactly that key on screen.
- **Diagnosis:** `od -c` shows `l i b - 7 c 1 e \n`, one byte more than expected.
- **Fix:** `stringData` (or `kubectl create secret --from-literal`) so nobody encodes by hand,
  or `echo -n`. Then restart the Pods: env vars are only read at container start, so
  updating the Secret alone changes nothing. After the restart, `200` with the loan counts.

![TS1 broken: 401, and od -c shows the \n in the Secret and in the env var](../screenshots/ts1-secret-newline-broken.png)

![TS1 fixed: 8 bytes, rollout restart, 200 with the right key and 401 with a wrong one](../screenshots/ts1-secret-newline-fixed.png)

## 2. ConfigMap key that does not exist

[`02-configmap-missing-key/`](02-configmap-missing-key): the Pod references
`FINE_PER_DAYS`, the ConfigMap has `FINE_PER_DAY`.

```bash
kubectl apply -f 02-configmap-missing-key/configmap.yaml -f 02-configmap-missing-key/pod-broken.yaml
kubectl get pod fine-calculator
kubectl describe pod fine-calculator | sed -n '/^Events/,$p'
kubectl get configmap fine-policy -o jsonpath='{.data}'; echo

kubectl delete pod fine-calculator
kubectl apply -f 02-configmap-missing-key/pod-fixed.yaml
kubectl logs fine-calculator
```

- **Symptom:** status `CreateContainerConfigError`. The container never starts, so
  `kubectl logs` has nothing to show.
- **Diagnosis:** the Event says `couldn't find key FINE_PER_DAYS in ConfigMap
  library/fine-policy`. Comparing with `.data` shows the typo. (A missing ConfigMap gives
  the same status with `configmap "..." not found`.)
- **Fix:** correct the key. Pod env is immutable, so the Pod is deleted and recreated. If a
  key is genuinely optional, `optional: true` on the `configMapKeyRef` lets the Pod start
  without it. The fixed Pod logs `fine per day: 0.50, cap: 10.00`.

![TS2 broken: CreateContainerConfigError and the couldn't find key event](../screenshots/ts2-configmap-key-broken.png)

![TS2 fixed: Pod Running and its log line](../screenshots/ts2-configmap-key-fixed.png)

## 3. Ingress points at a Service that does not exist

[`03-ingress-wrong-service/`](03-ingress-wrong-service): host `catalog.library.local` → Service
`catalog-service`, but the Service is called `catalog-api`.

```bash
kubectl apply -f 03-ingress-wrong-service/ingress-broken.yaml
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: catalog.library.local' http://localhost:8080/
kubectl describe ingress catalog-direct
kubectl get svc
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=20 | grep -i catalog-service

kubectl apply -f 03-ingress-wrong-service/ingress-fixed.yaml
curl -s -H 'Host: catalog.library.local' http://localhost:8080/
```

- **Symptom:** `503 Service Temporarily Unavailable` from the controller. The Ingress itself
  was accepted without any error (it gets an ADDRESS once the controller syncs its status;
  8 seconds in, on this run, the column was still empty).
- **Diagnosis:** `describe ingress` shows the backend as
  `catalog-service:8000 (<error: services "catalog-service" not found>)`; the controller log
  has a matching warning. `kubectl get svc` shows the real name.
- **Fix:** use the real Service name and port. After applying, the same curl returns the
  `catalog-api` text.

![TS3 broken: 503, the not found error in describe, the real Service list, and the controller log](../screenshots/ts3-ingress-service-broken.png)

![TS3 fixed: backend resolves to Pod IPs and the curl returns catalog-api](../screenshots/ts3-ingress-service-fixed.png)

## 4. Wrong `ingressClassName`

[`04-wrong-ingress-class/`](04-wrong-ingress-class): `ingressClassName: traefik` on a cluster that
only has `nginx`.

```bash
kubectl apply -f 04-wrong-ingress-class/ingress-broken.yaml
kubectl get ingress catalog-classcheck              # CLASS traefik, ADDRESS stays empty
kubectl get ingressclass
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: class.library.local' http://localhost:8080/
kubectl describe ingress catalog-classcheck | sed -n '/^Events/,$p'

kubectl apply -f 04-wrong-ingress-class/ingress-fixed.yaml
kubectl get ingress catalog-classcheck -w           # ADDRESS appears; Ctrl-C
curl -s -H 'Host: class.library.local' http://localhost:8080/
```

- **Symptom:** `404` from nginx for that host, the Ingress has no ADDRESS and no Events. It
  looks exactly like "the rules are wrong", but the rules are fine.
- **Diagnosis:** the `CLASS` column says `traefik`, and `kubectl get ingressclass` lists only
  `nginx`. No controller claims the Ingress, so it is silently ignored.
- **Fix:** set `ingressClassName` to an existing class (or omit it if the cluster has a
  default IngressClass, which `minikube addons enable ingress` sets up). The fixed Ingress
  returns the `catalog-api` text.

![TS4 broken: CLASS traefik, empty ADDRESS after 60 s, only nginx exists, 404, no Events](../screenshots/ts4-ingress-class-broken.png)

![TS4 fixed: ADDRESS, Sync event and the catalog-api response](../screenshots/ts4-ingress-class-fixed.png)

## 5. Service `targetPort` does not match the container

[`05-service-wrong-targetport/`](05-service-wrong-targetport): `renewals` (http-echo on
5678) behind a Service with `targetPort: 8080`, exposed on `renewals.library.local`.

```bash
kubectl apply -f 05-service-wrong-targetport/renewals-broken.yaml
kubectl rollout status deploy/renewals
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: renewals.library.local' http://localhost:8080/
kubectl get endpointslices -l kubernetes.io/service-name=renewals
kubectl get pod -l app=renewals -o jsonpath='{.items[0].spec.containers[0].ports}'; echo
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=20 | grep -i 'connection refused'

kubectl apply -f 05-service-wrong-targetport/renewals-fixed.yaml
curl -s -H 'Host: renewals.library.local' http://localhost:8080/
```

- **Symptom:** `502 Bad Gateway`. The Pod is Running and Ready, the Service exists, and the
  Ingress has an ADDRESS, so every `get` looks healthy.
- **Diagnosis:** the EndpointSlice lists the Pod IP on port **8080**, while the container
  declares **5678**. The controller log shows `connect() failed (111: Connection refused)
  while connecting to upstream` with `<pod-ip>:8080`.
- **Fix:** `targetPort: 5678` (better: name the container port and use `targetPort: http`,
  as the main manifests do). The EndpointSlice switches to 5678 and the curl returns the
  renewals text. On this run ingress-nginx took about 20 seconds to pick up the changed
  endpoint port (the first curl straight after the apply still got `502`), so retry for a
  little while before deciding the fix did not work.

![TS5 broken: Pod Running, 502, EndpointSlice on 8080 vs containerPort 5678, connection refused in the controller log](../screenshots/ts5-service-port-broken.png)

![TS5 fixed: EndpointSlice on 5678 and 200 after 21 s](../screenshots/ts5-service-port-fixed.png)

## Which symptom means what

| Symptom | Most likely cause | Look at |
|---|---|---|
| `CreateContainerConfigError` | Missing ConfigMap/Secret, or missing key | `describe pod` Events |
| App rejects a value that "looks right" | Hidden whitespace/newline in a Secret | `base64 -d \| od -c` |
| Config change not picked up | Value consumed as env var (or `subPath`) | `rollout restart` |
| `404` from the controller | No matching host/path, or wrong/missing IngressClass | `get ingress` CLASS + ADDRESS, `get ingressclass` |
| `503` from the controller | Backend Service missing, or no ready endpoints | `describe ingress`, `get endpointslices` |
| `502` from the controller | Endpoints exist but nothing listens on that port | Service `targetPort` vs container port, controller logs |
| Browser shows "Fake Certificate" | TLS Secret missing, wrong name, or wrong namespace | `get secret`, `describe ingress` TLS |

## Cleanup

```bash
kill %1 2>/dev/null
kubectl delete -f 05-service-wrong-targetport/renewals-fixed.yaml -f 04-wrong-ingress-class/ingress-fixed.yaml \
  -f 03-ingress-wrong-service/ingress-fixed.yaml -f 02-configmap-missing-key/pod-fixed.yaml \
  -f 02-configmap-missing-key/configmap.yaml -f 01-secret-newline/loan-service.yaml \
  -f 01-secret-newline/secret-fixed.yaml --ignore-not-found
```
