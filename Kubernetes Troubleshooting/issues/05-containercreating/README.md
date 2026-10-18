# 05: Stuck in ContainerCreating

Object: `loan-service` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

The Pod mounts Secret `loan-db-credentials`, which doesn't exist. The Pod is scheduled, but the kubelet can't build its volumes, so the container is never created.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues get pod loan-service
kubectl -n lib-issues describe pod loan-service | sed -n '/Events/,$p'
kubectl -n lib-issues get secret
```

What to look for: `FailedMount ... secret "loan-db-credentials" not found`. A missing ConfigMap, an unbound PVC or a CNI failure also leave a Pod in `ContainerCreating`, and the events say which one it is.

## Fix

Create the Secret (the values in `fixed.yaml` are lab placeholders). The kubelet retries the mount on its own, so the existing Pod recovers without being deleted.

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: Within about a minute the Pod is `Running`, and `kubectl exec loan-service -- ls /etc/loan-db` lists `username` and `password`.

Screenshots: `../../screenshots/05-broken.png` and `../../screenshots/05-fixed.png`.
