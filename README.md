# Practice Session: Senior DevOps Engineer (Secrets Manager)

A self-run version of a live 2-hour technical session. Run it against your **local** Kubernetes cluster (Rancher Desktop, kind, Docker Desktop, minikube, etc.). No cloud account is needed.

| Real interview (likely) | This practice repo |
|---|---|
| AWS Secrets Manager | Kubernetes `Secret` |
| IAM role via IRSA | ServiceAccount + RBAC |
| EKS cluster, IP-allowlisted | Your local cluster |
| Their GitHub repo | Your own private GitHub repo |

The service is a small Python app. It is shipped through a ConfigMap and runs on `python:3.12-alpine`, so **you don't need to build an image**.

---

## Rules (same as tomorrow)

- **Timebox: 2 hours.** Start a timer.
- Your AI assistant is allowed **in ask/plan mode only**. You type and run every command yourself.
- **Think out loud.** Talking into the void counts. Better yet, record yourself.
- Use `kubectl edit`/`patch` for experiments if you like, but the **final fix must be in the Helm chart and delivered through a PR**.
- Don't read `scripts/verify.sh` to reverse-engineer the bugs. Treat it as a black-box acceptance test.

## Prerequisites

`kubectl`, `helm`, `git`, `make`, `jq`, and a GitHub account. On macOS: `brew install helm jq`.

---

## Part 0: Setup and access (≈10 min)

1. Create a **private** GitHub repo, for example `secrets-sync-practice`. Push this repo's `main` branch to it, then create a working branch.
2. Make sure `kubectl` is pointing at your **local** cluster. The scripts refuse to run against anything else unless you pass `FORCE=1`.
3. Run `make setup`. This creates the `secrets-sync` and `legacy-apps` namespaces and the `db-credentials` secret, which is owned by "another team" and is **not** part of the chart.
4. Run `make deploy`.

## Part 1: Investigate (≈30 min)

The `secrets-sync` deployment in the `secrets-sync` namespace is **not healthy**, and `make verify` fails.

- Find **all** the root causes. There is more than one, and some only show up after you fix the previous one.
- For each one, note the **symptom**, the **command that revealed it**, and the **root cause**. You'll need these for the PR description.

## Part 2: Fix through Git (≈30 min)

1. Fix the chart. Use `make deploy` to apply your changes and `make verify` to check them. **The goal is `ALL CHECKS PASSED`.**
2. Commit, push your branch, and open a PR to `main`. The PR description should cover:
   - each root cause → fix
   - how you verified it
   - risk and rollback notes
3. Make sure **CI is green** on the PR (`.github/workflows/ci.yaml`). Run `make lint` locally first.

## Part 3: Extend (≈30 min, choose one or more)

**A. Least privilege.** The app's RBAC is broader than it needs to be. Tighten it to exactly what the app uses, then prove it with `kubectl auth can-i ... --as=system:serviceaccount:...`, both for what should be allowed and for what should be denied.

**B. Secrets audit script.** Write `scripts/audit-secrets.sh` (bash + `kubectl` + `jq`) or `scripts/audit_secrets.py`. It should report every **application secret in the cluster** that:

- has no `owner` label, **or**
- has no `secrets.example.com/last-rotated` annotation, **or**
- was last rotated **more than 90 days ago**.

Output a readable table (namespace, name, owner, last-rotated, reasons) and exit non-zero if anything was found, so it could run in CI or on a cron. Think about which secrets are actually in scope. It must pass `shellcheck` in CI.

**C. Rotation without downtime.** `make verify-rotation` rotates the password. The running pods keep serving the old value, so the check fails. Make rotated secrets propagate to all pods **within 60 seconds, without restarting or replacing pods**, and make `make verify-rotation` pass. Then write a few lines in the PR comparing the alternatives you considered and why you chose this one.

## Part 4: Design discussion (≈20 min, out loud)

> "We now need to deliver secrets to ~500 microservices across 10 EKS clusters in 3 regions."

- Delivery mechanism: External Secrets Operator vs. the Secrets Store CSI Driver vs. a sidecar/agent vs. the app calling the secrets API directly. What are the trade-offs?
- Identity: how does each workload authenticate (IRSA / EKS Pod Identity), and how do you enforce least privilege **per service** at that scale?
- **Rotation** with zero downtime, including dual credentials and DB users that rotate.
- Audit, alerting on unusual access, multi-region replication and failover, and break-glass access.
- Rolling it out safely to 10 clusters: GitOps with ArgoCD ApplicationSets, sync waves, a canary cluster.
- What happens to every pod when the secrets backend is down?

---

## Useful targets

```
make help             list targets
make status           deploy/rs/pods/svc/endpoints
make logs             tail app logs
make verify           acceptance test for Parts 1-2
make verify-rotation  acceptance test for Part 3C
make reset            wipe everything and start over (then: make setup && make deploy)
```
