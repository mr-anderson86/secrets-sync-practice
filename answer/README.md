# secrets-sync: bugs, root cause and fixes

## Symptom

The pod was in `Error` / CrashLoopBackOff and the log ended with:

```
{"level": "fatal", "msg": "failed to load secret", "error": "Kubernetes API returned 403 reading secret secrets-sync/db-credentials: secrets \"db-credentials\" is forbidden: User \"system:serviceaccount:secrets-sync:secrets-sync\" cannot get resource \"secrets\" in API group \"\" in the namespace \"secrets-sync\""}
```

## Bugs, root causes and fixes

### 1. RoleBinding bound to the wrong namespace (the 403)

- **File:** `helm/secrets-sync/templates/rbac.yaml`
- **Root cause:** the RoleBinding subject had a hard-coded `namespace: default`. The Role was therefore granted to `default/secrets-sync`, not to the ServiceAccount `secrets-sync/secrets-sync` that the pod runs as. The Role and RoleBinding existed, but granted nothing to the pod.
- **Fix:**
  ```yaml
  subjects:
    - kind: ServiceAccount
      name: {{ include "secrets-sync.serviceAccountName" . }}
      namespace: {{ .Release.Namespace }}
  ```

### 2. Deployment referenced a ServiceAccount that does not exist

- **File:** `helm/secrets-sync/templates/deployment.yaml`
- **Root cause:** `serviceAccountName` was `{{ include "secrets-sync.fullname" . }}-sa`, but the ServiceAccount is created under the name from the `secrets-sync.serviceAccountName` helper (no `-sa` suffix). The Deployment and the RBAC objects were not talking about the same account.
- **Fix:** `serviceAccountName: {{ include "secrets-sync.serviceAccountName" . }}`

### 3. Readiness probe on the wrong port

- **File:** `helm/secrets-sync/templates/deployment.yaml`
- **Root cause:** the readiness probe targeted port `8081`, but the app only listens on `PORT=8080` (`/healthz` and `/ready` are served by the same server). The pod would never become Ready.
- **Fix:** `port: http` (the named container port, 8080).

### 4. Service selector did not match the pods

- **File:** `helm/secrets-sync/templates/service.yaml`
- **Root cause:** the selector was `app: <fullname>`, but the pods are labelled `app.kubernetes.io/name` and `app.kubernetes.io/instance`. The Service had no endpoints.
- **Fix:** use the shared helper so the selector and pod labels cannot drift apart:
  ```yaml
  selector:
    {{- include "secrets-sync.selectorLabels" . | nindent 4 }}
  ```

### 5. Wrong secret key name in values

- **File:** `helm/secrets-sync/values.yaml`
- **Root cause:** `secret.key` was `db-password`, but the secret `db-credentials` is not created by the chart. It is created by `scripts/setup.sh` with the keys `username` and `password`. Once the 403 was fixed, the app would fail with "key 'db-password' not found".
- **Fix:** `secret.key: password`. The `username` key is not used by the app and needs no change.

## How it was diagnosed

1. The log showed a 403 for the ServiceAccount `secrets-sync:secrets-sync`, so the RBAC chain was checked first: `kubectl -n secrets-sync get role,rolebinding,serviceaccount -o yaml`. The Role and ServiceAccount were fine, but the RoleBinding subject namespace was `default`.
2. The templates were compared against the app (`helm/secrets-sync/files/app.py`): the listening port (8080) and the pod labels exposed bugs 2, 3 and 4.
3. `scripts/setup.sh` and `kubectl get secret db-credentials` showed which keys the secret really has, exposing bug 5.

## Verification

```bash
helm lint helm/secrets-sync
helm template secrets-sync helm/secrets-sync -n secrets-sync   # check namespace, probe port, selector
helm upgrade secrets-sync helm/secrets-sync -n secrets-sync

kubectl auth can-i get secret/db-credentials -n secrets-sync \
  --as=system:serviceaccount:secrets-sync:secrets-sync          # yes
kubectl -n secrets-sync get pods,endpoints                      # pods 1/1 Ready, endpoints populated
```

## Optional hardening (not applied)

The Role grants `get`, `list` and `watch` on all secrets in the namespace, but the app only does a GET on one secret. It could be tightened to:

```yaml
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["db-credentials"]
    verbs: ["get"]
```
