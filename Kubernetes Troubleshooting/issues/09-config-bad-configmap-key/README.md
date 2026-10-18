# 09: Missing ConfigMap key

Object: `branch-info` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

`configMapKeyRef.key` is `BRANCH_COD`, but the ConfigMap's key is `BRANCH_CODE`.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues get pod branch-info
kubectl -n lib-issues describe pod branch-info | sed -n '/Events/,$p'
kubectl -n lib-issues get configmap branch-settings -o jsonpath='{.data}'
```

What to look for: The status is `CreateContainerConfigError`, with the event `couldn't find key BRANCH_COD in ConfigMap lib-issues/branch-settings`. The container was never created, so there are no logs.

## Fix

Fix the key name. (`optional: true` would also let the Pod start, but the variable would be empty, which only hides the bug.)

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: The Pod is `Running`, and the log prints `branch=CENTRAL-01`.

Screenshots: `../../screenshots/09-broken.png` and `../../screenshots/09-fixed.png`.
