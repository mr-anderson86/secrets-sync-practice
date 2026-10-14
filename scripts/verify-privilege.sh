#!/usr/bin/env bash
# Checks the app's ServiceAccount has exactly the RBAC it needs (Part 3A):
# allowed to get its own secret, denied everything else.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl
check_context

SECRET="${SECRET:-db-credentials}"
SA="system:serviceaccount:$APP_NS:$RELEASE"
fail=0

# expect <yes|no> <verb> <resource> [namespace]
# Reads can-i's stdout, not its exit code: it exits 1 for "no" AND for errors,
# which would turn an error into a false PASS on a deny check.
expect() {
  local want="$1" verb="$2" res="$3" ns="${4:-$APP_NS}" got
  if [ -n "${DEBUG:-}" ]; then
    echo kubectl auth can-i "$verb" "$res" -n "$ns" --as="$SA"
  fi
  got="$(kubectl auth can-i "$verb" "$res" -n "$ns" --as="$SA" 2>/dev/null || true)"
  [ -n "$got" ] || got="error"
  if [ "$got" = "$want" ]; then
    printf '  %s  %-7s %s -> %s\n' "$(green PASS)" "$verb" "$ns/$res" "$got"
  else
    printf '  %s  %-7s %s -> %s (expected %s)\n' "$(red FAIL)" "$verb" "$ns/$res" "$got" "$want"
    fail=1
  fi
}

info "checking RBAC for $SA"
expect yes get    "secrets/$SECRET"
expect no  get    "secrets/not-$SECRET"
expect no  list   secrets
expect no  watch  secrets
expect no  create secrets
expect no  update "secrets/$SECRET"
expect no  delete "secrets/$SECRET"
expect no  get    secrets/payments-db "$LEGACY_NS"
expect no  list   pods

if [ "$fail" = 0 ]; then
  green "ALL RBAC CHECKS PASSED"
else
  red "RBAC is broader (or narrower) than the app needs"
  exit 1
fi
