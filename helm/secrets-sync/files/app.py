"""secrets-sync: tiny demo service that loads a DB credential from a Kubernetes Secret.

It talks to the Kubernetes API directly using its ServiceAccount token (the in-cluster
equivalent of an app calling AWS Secrets Manager with an IRSA role).

Endpoints:
  /healthz  -> 200 while the process is alive
  /ready    -> 200 once the secret was loaded successfully, 503 otherwise
  /version  -> JSON with a short fingerprint of the loaded secret value (never the value itself)

Environment:
  SECRET_NAME               (required) name of the Secret in the pod's own namespace
  SECRET_KEY                key inside the Secret to read (default: "password")
  PORT                      HTTP port (default: 8080)
  REFRESH_INTERVAL_SECONDS  0 = load once at startup (default). >0 = re-read the Secret
                            periodically; on refresh errors the last good value is kept.
"""
import base64
import hashlib
import json
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SA_DIR = os.environ.get("SA_DIR", "/var/run/secrets/kubernetes.io/serviceaccount")
SECRET_NAME = os.environ.get("SECRET_NAME", "")
SECRET_KEY = os.environ.get("SECRET_KEY", "password")
PORT = int(os.environ.get("PORT", "8080"))
REFRESH = int(os.environ.get("REFRESH_INTERVAL_SECONDS", "0"))

state = {"ready": False, "version": None, "loaded_at": None}
lock = threading.Lock()


def log(level, msg, **fields):
    rec = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), "level": level, "msg": msg}
    rec.update(fields)
    print(json.dumps(rec), flush=True)


class LoadError(Exception):
    pass


def api_base():
    host = os.environ.get("KUBERNETES_SERVICE_HOST")
    port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
    if not host:
        raise LoadError("KUBERNETES_SERVICE_HOST is not set - not running inside a cluster?")
    if ":" in host:  # IPv6
        host = f"[{host}]"
    return f"https://{host}:{port}"


def read_sa_file(name):
    path = os.path.join(SA_DIR, name)
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError as e:
        raise LoadError(f"cannot read {path}: {e.strerror} (is a ServiceAccount token mounted?)")


def load_secret():
    token = read_sa_file("token")
    namespace = read_sa_file("namespace")
    ctx = ssl.create_default_context(cafile=os.path.join(SA_DIR, "ca.crt"))
    url = f"{api_base()}/api/v1/namespaces/{namespace}/secrets/{SECRET_NAME}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=5) as resp:
            secret = json.load(resp)
    except urllib.error.HTTPError as e:
        try:
            detail = json.load(e).get("message", "")
        except Exception:
            detail = ""
        raise LoadError(f"Kubernetes API returned {e.code} reading secret {namespace}/{SECRET_NAME}: {detail}")
    except urllib.error.URLError as e:
        raise LoadError(f"cannot reach Kubernetes API at {url}: {e.reason}")

    data = secret.get("data") or {}
    if SECRET_KEY not in data:
        raise LoadError(
            f"key '{SECRET_KEY}' not found in secret {namespace}/{SECRET_NAME}; "
            f"available keys: {sorted(data.keys())}"
        )
    value = base64.b64decode(data[SECRET_KEY])
    return hashlib.sha256(value).hexdigest()[:12]


def refresh_loop():
    while True:
        time.sleep(REFRESH)
        try:
            version = load_secret()
        except LoadError as e:
            log("error", "secret refresh failed, keeping last good value", error=str(e))
            continue
        with lock:
            if version != state["version"]:
                log("info", "secret rotated", old_version=state["version"], new_version=version)
                state["version"] = version
                state["loaded_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        with lock:
            snapshot = dict(state)
        if self.path == "/healthz":
            self._send(200, {"status": "ok"})
        elif self.path == "/ready":
            if snapshot["ready"]:
                self._send(200, {"status": "ready"})
            else:
                self._send(503, {"status": "not ready"})
        elif self.path == "/version":
            self._send(200, {
                "secret": SECRET_NAME,
                "secret_version": snapshot["version"],
                "loaded_at": snapshot["loaded_at"],
                "hostname": os.environ.get("HOSTNAME"),
            })
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):  # keep probe noise out of the logs
        pass


def main():
    if not SECRET_NAME:
        log("fatal", "SECRET_NAME environment variable is required")
        sys.exit(1)
    log("info", "starting secrets-sync", secret=SECRET_NAME, key=SECRET_KEY, port=PORT, refresh_seconds=REFRESH)
    try:
        version = load_secret()
    except LoadError as e:
        log("fatal", "failed to load secret", error=str(e))
        sys.exit(1)
    with lock:
        state.update(ready=True, version=version,
                     loaded_at=datetime.now(timezone.utc).isoformat(timespec="seconds"))
    log("info", "secret loaded", secret_version=version)

    if REFRESH > 0:
        threading.Thread(target=refresh_loop, daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log("info", "listening", port=PORT)
    server.serve_forever()


if __name__ == "__main__":
    main()
