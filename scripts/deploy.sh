#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl helm
check_context
info "helm upgrade --install $RELEASE"
helm upgrade --install "$RELEASE" "$(dirname "$0")/../helm/secrets-sync" \
  --namespace "$APP_NS" "$@"
green "deployed. it's not supposed to work yet :) - start investigating."
