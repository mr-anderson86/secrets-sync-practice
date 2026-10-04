#!/usr/bin/env bash
# Creates the out-of-band resources the service depends on (owned by "another team"),
# plus some legacy secrets for the audit exercise.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl
check_context

today="$(date -u +%Y-%m-%d)"

info "creating namespaces"
kubectl create namespace "$APP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$LEGACY_NS" --dry-run=client -o yaml | kubectl apply -f -

# make_secret <ns> <name> <owner|-> <last-rotated|-> key=value...
make_secret() {
  local ns="$1" name="$2" owner="$3" rotated="$4"
  shift 4
  local args=()
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  kubectl -n "$ns" create secret generic "$name" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if [ "$owner" != "-" ]; then
    kubectl -n "$ns" label secret "$name" owner="$owner" --overwrite >/dev/null
  fi
  if [ "$rotated" != "-" ]; then
    kubectl -n "$ns" annotate secret "$name" secrets.example.com/last-rotated="$rotated" --overwrite >/dev/null
  fi
  echo "   $ns/$name"
}

info "creating application secret"
if kubectl -n "$APP_NS" get secret db-credentials >/dev/null 2>&1; then
  echo "   $APP_NS/db-credentials already exists - leaving it as is"
else
  make_secret "$APP_NS" db-credentials platform "$today" username=app_user "password=$(random_password)"
fi

info "creating legacy secrets (for the audit exercise)"
make_secret "$LEGACY_NS" payments-db       payments "$today"    username=pay "password=$(random_password)"
make_secret "$LEGACY_NS" legacy-ftp        -        2025-01-15  username=ftp "password=$(random_password)"
make_secret "$LEGACY_NS" reporting-api-key bi       2026-03-01  "api-key=$(random_password)"
make_secret "$LEGACY_NS" old-smtp          platform -           "password=$(random_password)"
make_secret "$LEGACY_NS" search-token      search   "$today"    "token=$(random_password)"

green "setup done. next: make deploy"
