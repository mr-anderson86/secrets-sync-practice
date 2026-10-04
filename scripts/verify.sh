#!/usr/bin/env bash
# Checks that the service is actually healthy end to end. Exits non-zero on failure.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl
fail=0
check() { if eval "$2" >/dev/null 2>&1; then green "  PASS  $1"; else red "  FAIL  $1"; fail=1; fi; }

info "verifying $APP_NS/$RELEASE"
desired="$(kubectl -n "$APP_NS" get deploy "$RELEASE" -o jsonpath='{.spec.replicas}' 2>/dev/null)"
ready="$(kubectl -n "$APP_NS" get deploy "$RELEASE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
check "deployment exists" "[ -n '$desired' ]"
check "all replicas ready (${ready:-0}/${desired:-?})" "[ -n '$desired' ] && [ '${ready:-0}' = '$desired' ]"

restarts="$(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/instance="$RELEASE" \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | sort -n | tail -1)"
info "max restart count across pods: ${restarts:-n/a} (should stay flat from now on)"

eps="$(kubectl -n "$APP_NS" get endpoints "$RELEASE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)"
check "service has endpoints" "[ -n '$eps' ]"
check "GET /ready through the Service returns 200" \
  "kubectl get --raw /api/v1/namespaces/$APP_NS/services/$RELEASE:http/proxy/ready"

expected="$(kubectl -n "$APP_NS" get secret db-credentials -o jsonpath='{.data.password}' 2>/dev/null | base64 -d | sha12)"
for pod in $(kubectl -n "$APP_NS" get pods -l app.kubernetes.io/instance="$RELEASE" -o name 2>/dev/null); do
  p="${pod#pod/}"
  got="$(kubectl get --raw "/api/v1/namespaces/$APP_NS/pods/$p:8080/proxy/version" 2>/dev/null \
    | sed -n 's/.*"secret_version": *"\([0-9a-f]*\)".*/\1/p')"
  check "$p serves the current secret (expected $expected, got ${got:-none})" "[ '$got' = '$expected' ]"
done

if [ "$fail" = 0 ]; then green "ALL CHECKS PASSED"; else red "SOME CHECKS FAILED"; fi
exit "$fail"
