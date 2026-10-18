# 08: Pod-to-Pod networking

Object: `loan-service / desk-client` in namespace `lib-issues`. Run the commands from this folder.

## What is wrong

Two separate faults. **(a)** `loan-service` binds its HTTP server to `127.0.0.1:8080`, so it only accepts connections from inside its own network namespace. **(b)** After that is fixed, `networkpolicy-deny.yaml` drops all ingress in the namespace.

## Reproduce

```bash
kubectl create namespace lib-issues --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lib-issues apply -f broken.yaml
```

## Diagnose

```bash
kubectl -n lib-issues logs desk-client --tail=3
kubectl -n lib-issues exec loan-service -- wget -qO- http://127.0.0.1:8080   # works from inside
kubectl -n lib-issues exec loan-service -- netstat -tln                      # 127.0.0.1:8080
kubectl -n lib-issues get netpol
```

What to look for: (a) gives `Connection refused`: the host is reachable but nothing is listening on the Pod IP. (b) gives a timeout: the packets are silently dropped. That difference tells you which layer to look at. NetworkPolicy is only enforced when the CNI supports it, for example `minikube start --cni=calico`.

## Fix

(a) Apply `fixed.yaml` (bind `0.0.0.0`). (b) Apply `networkpolicy-deny.yaml` to see the timeout, then `networkpolicy-allow.yaml` to let only `desk-client` reach port 8080.

```bash
kubectl -n lib-issues delete -f broken.yaml --ignore-not-found
kubectl -n lib-issues apply -f fixed.yaml
kubectl -n lib-issues apply -f networkpolicy-deny.yaml    # fault (b)
kubectl -n lib-issues apply -f networkpolicy-allow.yaml   # fix (b)
```

Expected after the fix: `desk-client` logs `loans: 42 active` every 5 s. A Pod without the `app=desk-client` label still times out while the deny policy is in place.

Screenshots: `../../screenshots/08-broken.png` and `../../screenshots/08-fixed.png`.
