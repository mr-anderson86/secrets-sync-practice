#!/usr/bin/env bash
# Simulates the security team rotating the DB password.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl
new="$(random_password)"
b64="$(printf '%s' "$new" | base64 | tr -d '\n')"
kubectl -n "$APP_NS" patch secret db-credentials --type merge \
  -p "{\"data\":{\"password\":\"$b64\"}}" >/dev/null
kubectl -n "$APP_NS" annotate secret db-credentials \
  secrets.example.com/last-rotated="$(date -u +%Y-%m-%d)" --overwrite >/dev/null
green "rotated $APP_NS/db-credentials -> new version $(printf '%s' "$new" | sha12)"
