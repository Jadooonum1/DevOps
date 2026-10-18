#!/usr/bin/env bash
# triage.sh - run the five-scenario troubleshooting gauntlet and print a triage report.
#
# Usage: ./triage.sh <deploy|report|fix|clean> [namespace]
#   deploy  create the namespace and apply every scenario-*/broken.yaml
#   report  for each gauntlet Pod: status, restarts, last exit, newest Warning event,
#           last log line and a hint about where to look next
#   fix     replace each broken Pod with scenario-*/fixed.yaml
#   clean   delete the namespace
#
# Author: Parth Agarwal
set -euo pipefail

ACTION="${1:-}"
NS="${2:-lib-gauntlet}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTLE="${SETTLE:-45}"

die() { echo "error: $*" >&2; exit 1; }
command -v kubectl >/dev/null || die "kubectl not found"

# jsonpath lookup that never aborts the script (missing fields are normal here)
jp() { kubectl -n "$NS" get pod "$1" -o "jsonpath=$2" 2>/dev/null || true; }

classify() {
  # Prefer the last termination reason: an OOMKilled or crashing container is often
  # caught "Running" between restarts, so its current state alone is misleading.
  local pod="$1" waiting last phase
  waiting=$(jp "$pod" '{.status.containerStatuses[0].state.waiting.reason}')
  last=$(jp "$pod" '{.status.containerStatuses[0].lastState.terminated.reason}')
  phase=$(jp "$pod" '{.status.phase}')
  if [[ "$last" == "OOMKilled" ]]; then echo "OOMKilled"
  elif [[ -n "$waiting" ]]; then echo "$waiting"
  else echo "${phase:-Unknown}"
  fi
}

hint() {
  case "$1" in
    CrashLoopBackOff|Error)        echo "process exits after start: kubectl logs --previous, check exit code" ;;
    ErrImagePull|ImagePullBackOff) echo "image name/tag/registry/credentials: read the pull event message" ;;
    Pending)                       echo "not scheduled: FailedScheduling event (resources, nodeSelector, taints, PVC)" ;;
    OOMKilled)                     echo "exit 137: memory limit below the real working set" ;;
    CreateContainerConfigError)    echo "referenced ConfigMap/Secret or key missing" ;;
    ContainerCreating)             echo "volume mount or network setup failing: check events" ;;
    Running)                       echo "status looks fine; app-level errors only show up in the logs" ;;
    *)                             echo "kubectl describe pod and read Events" ;;
  esac
}

deploy() {
  kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null
  local f count=0
  for f in "$HERE"/scenario-*/broken.yaml; do
    kubectl -n "$NS" apply -f "$f" >/dev/null
    count=$((count + 1))
  done
  echo "applied $count broken scenarios to namespace $NS"
  echo "waiting ${SETTLE}s for the failures to show (override with SETTLE=...)"
  sleep "$SETTLE"
  report
}

report() {
  kubectl -n "$NS" get pods -l gauntlet=true -o wide
  echo
  local pods pod status restarts exitcode event logline
  pods=$(kubectl -n "$NS" get pods -l gauntlet=true -o jsonpath='{.items[*].metadata.name}')
  [[ -z "$pods" ]] && die "no gauntlet Pods in $NS (run: $0 deploy $NS)"
  for pod in $pods; do
    status=$(classify "$pod")
    restarts=$(jp "$pod" '{.status.containerStatuses[0].restartCount}')
    exitcode=$(jp "$pod" '{.status.containerStatuses[0].lastState.terminated.exitCode}')
    event=$(kubectl -n "$NS" get events \
              --field-selector "involvedObject.name=$pod,type=Warning" \
              --sort-by=.lastTimestamp \
              -o jsonpath='{range .items[-1:]}{.reason}: {.message}{end}' 2>/dev/null | cut -c1-110 || true)
    logline=$(kubectl -n "$NS" logs "$pod" --tail=1 2>/dev/null || true)
    if [[ -z "$logline" ]]; then
      logline=$(kubectl -n "$NS" logs "$pod" --previous --tail=1 2>/dev/null || true)
    fi
    printf '%-18s %s (restarts=%s%s)\n' "$pod" "$status" "${restarts:-0}" "${exitcode:+, last exit=$exitcode}"
    printf '  hint : %s\n' "$(hint "$status")"
    [[ -n "$event" ]]   && printf '  event: %s\n' "$event"
    [[ -n "$logline" ]] && printf '  log  : %s\n' "$logline"
    echo
  done
}

fix() {
  local d
  for d in "$HERE"/scenario-*/; do
    kubectl -n "$NS" delete -f "$d/broken.yaml" --ignore-not-found --wait=false >/dev/null
  done
  kubectl -n "$NS" wait --for=delete pod -l gauntlet=true --timeout=90s >/dev/null 2>&1 || true
  for d in "$HERE"/scenario-*/; do
    kubectl -n "$NS" apply -f "$d/fixed.yaml" >/dev/null
    echo "applied $(basename "$d")/fixed.yaml"
  done
  kubectl -n "$NS" wait --for=condition=Ready pod -l gauntlet=true --timeout=120s || true
  report
}

clean() { kubectl delete ns "$NS" --ignore-not-found; }

case "$ACTION" in
  deploy) deploy ;;
  report) report ;;
  fix)    fix ;;
  clean)  clean ;;
  *) echo "usage: $0 <deploy|report|fix|clean> [namespace]" >&2; exit 2 ;;
esac
