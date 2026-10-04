#!/usr/bin/env bash
# Removes everything so you can start the exercise from scratch.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl helm
check_context
helm uninstall "$RELEASE" -n "$APP_NS" 2>/dev/null || true
kubectl delete namespace "$APP_NS" "$LEGACY_NS" --ignore-not-found
green "reset done"
