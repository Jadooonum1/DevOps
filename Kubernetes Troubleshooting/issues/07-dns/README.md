# 07: DNS resolution failure

Object: `dns-client` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

`dns-client` uses `dnsPolicy: None` with the nameserver `192.0.2.53` (a documentation address with nothing behind it), so it never asks CoreDNS.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues logs dns-client --tail=5
kubectl -n lib-issues exec dns-client -- cat /etc/resolv.conf
kubectl -n kube-system get svc kube-dns
kubectl -n lib-issues run dnscheck --rm -it --image=busybox:1.36 --restart=Never -- nslookup shelf-target
```

What to look for: The logs show timeouts and `LOOKUP FAILED`. `resolv.conf` lists `192.0.2.53` rather than the `kube-dns` ClusterIP. A throwaway Pod with default settings resolves `shelf-target` without trouble, which proves CoreDNS is healthy and the client Pod is misconfigured.

## Fix

Go back to `dnsPolicy: ClusterFirst`. DNS settings can't be changed in place, so delete and re-create `dns-client`.

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
```

Expected after the fix: `nslookup` returns `shelf-target.lib-issues.svc.cluster.local` with the Service IP.

Screenshots: `../../screenshots/07-broken.png` and `../../screenshots/07-fixed.png`.
