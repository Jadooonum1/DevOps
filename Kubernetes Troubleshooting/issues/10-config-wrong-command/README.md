# 10: Wrong command

Object: `opac-frontend` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

`command: ["ngnix", ...]` replaces the image ENTRYPOINT with a binary that doesn't exist. The container runtime fails at `exec`, before any application code runs.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues get pod opac-frontend
kubectl -n lib-issues get pod opac-frontend -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'; echo
kubectl -n lib-issues describe pod opac-frontend | grep -E 'Reason|Exit Code|Message'
```

What to look for: The status is `RunContainerError` / `StartError`, later `CrashLoopBackOff`. The message says `exec: "ngnix": executable file not found in $PATH`, with **exit code 128**. Compare with 01, where the app ran and chose exit 1. When Docker runs the same typo through the image's entrypoint script, it shows up as shell exit 127 instead.

## Fix

Spell the binary correctly, or drop `command` and keep the image's default.

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: `Running`, 0 restarts.

Screenshots: `../../screenshots/10-broken.png` and `../../screenshots/10-fixed.png`.
