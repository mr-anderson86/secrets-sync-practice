#!/usr/bin/env bash
# Rotates the secret and waits up to 90s for every pod to pick it up WITHOUT restarting.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl
dir="$(dirname "$0")"

pods_before="$(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/instance="$RELEASE" -o name | sort | tr '\n' ' ')"
"$dir/rotate.sh"
expected="$(kubectl -n "$APP_NS" get secret db-credentials -o jsonpath='{.data.password}' | base64 -d | sha12)"

info "waiting up to 90s for all pods to serve version $expected"
for _ in $(seq 1 18); do
  stale=0
  for pod in $pods_before; do
    p="${pod#pod/}"
    got="$(kubectl get --raw "/api/v1/namespaces/$APP_NS/pods/$p:8080/proxy/version" 2>/dev/null \
      | sed -n 's/.*"secret_version": *"\([0-9a-f]*\)".*/\1/p' || true)"
    [ "$got" = "$expected" ] || stale=1
  done
  if [ "$stale" = 0 ]; then
    pods_after="$(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/instance="$RELEASE" -o name | sort | tr '\n' ' ')"
    if [ "$pods_before" = "$pods_after" ]; then
      green "PASS: all pods picked up the rotated secret, no restarts/replacements needed"
    else
      red "PARTIAL: pods serve the new secret, but they were replaced (rollout) - can you avoid that?"
    fi
    exit 0
  fi
  sleep 5
done
red "FAIL: after 90s some pods still serve the old secret version"
exit 1
