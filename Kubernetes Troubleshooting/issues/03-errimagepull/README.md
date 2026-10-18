# 03: ErrImagePull (unreachable registry)

Object: `barcode-scanner` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

The image points to `registry.library.invalid`. `.invalid` is a reserved TLD that never resolves, so the node can't even reach a registry. This is a different failure from 02, where the registry answered "no such tag".

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues get pod barcode-scanner -w
kubectl -n lib-issues get events --field-selector involvedObject.name=barcode-scanner
```

What to look for: Status alternates between `ErrImagePull` and `ImagePullBackOff`. The event message contains `dial tcp: lookup registry.library.invalid ... no such host`. Read the error text, not only the status: *no such host* is a DNS or registry-address problem, *not found* is a wrong name or tag, and *unauthorized* means `imagePullSecrets` are missing.

## Fix

Use an image from a reachable registry (here `nginx:1.27-alpine`).

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: `Running` within a few seconds.

Screenshots: `../../screenshots/03-broken.png` and `../../screenshots/03-fixed.png`.
