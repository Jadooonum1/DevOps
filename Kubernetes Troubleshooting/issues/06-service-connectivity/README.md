# 06: Service connectivity

Object: `catalog-api` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

Both Pods are Running and Ready, and the selector matches. The Service, however, forwards to `targetPort: 8080`, and nginx listens on 80.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues get svc,endpointslices -l issue=06
kubectl -n lib-issues run probe --rm -it --image=busybox:1.36 --restart=Never -- wget -T 3 -qO- http://catalog-api
kubectl -n lib-issues get endpointslices -l kubernetes.io/service-name=catalog-api -o yaml | grep -A2 ports
```

What to look for: The request fails with `Connection refused`. The EndpointSlice is **not** empty (both Pod IPs are listed), but its port is 8080. Read it like this: no endpoints means a selector or readiness problem, while endpoints with the wrong port means a `targetPort` problem.

## Fix

Set `targetPort: 80` (or a named port, which keeps the Service right if the container port changes later).

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: The same `wget` returns the nginx welcome page.

Screenshots: `../../screenshots/06-broken.png` and `../../screenshots/06-fixed.png`.
