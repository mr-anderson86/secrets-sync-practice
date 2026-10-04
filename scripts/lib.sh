#!/usr/bin/env bash
# Shared helpers. Written for bash 3.2 (macOS default) as well as bash 5.
APP_NS="${APP_NS:-secrets-sync}"
LEGACY_NS="${LEGACY_NS:-legacy-apps}"
RELEASE="${RELEASE:-secrets-sync}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }

sha12() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -c1-12
  else sha256sum | cut -c1-12; fi
}

random_password() {
  # head closes the pipe after 24 chars, so tr dies with SIGPIPE (141);
  # swallow that so pipefail/set -e callers don't abort.
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true
}

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || { red "missing required tool: $bin"; exit 1; }
  done
}

check_context() {
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  [ -n "$ctx" ] || { red "no current kubectl context"; exit 1; }
  case "$ctx" in
    rancher-desktop|docker-desktop|minikube|kind-*|k3d-*|orbstack|colima*) ;;
    *)
      if [ "${FORCE:-}" != "1" ]; then
        red "current context is '$ctx' - doesn't look like a local cluster."
        red "re-run with FORCE=1 if you're sure."
        exit 1
      fi ;;
  esac
  info "using kubectl context: $ctx"
}
