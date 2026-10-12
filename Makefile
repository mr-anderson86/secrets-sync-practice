VENV := .venv

.PHONY: help setup deploy status verify rotate verify-rotation verify-privilege audit-secrets logs lint reset

help:            ## show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

setup:           ## create namespaces + out-of-band secrets (run once)
	@./scripts/setup.sh

deploy:          ## helm upgrade --install the service
	@./scripts/deploy.sh

status:          ## quick look at what's running
	kubectl -n secrets-sync get deploy,rs,pods,svc,endpoints -o wide

verify:          ## end-to-end health check (your goal for Parts 1-2)
	@./scripts/verify.sh

rotate:          ## rotate the DB password (simulates the security team)
	@./scripts/rotate.sh

verify-rotation: ## rotate + check pods pick it up without restarting (Part 3C)
	@./scripts/verify-rotation.sh

verify-privilege: ## check the app SA has least-privilege RBAC (Part 3A)
	@./scripts/verify-privilege.sh

audit-secrets: $(VENV)/.installed ## report app secrets missing owner/rotation or rotated >90d (Part 3B)
	@$(VENV)/bin/python scripts/audit_secrets.py $(ARGS)

# venv for the Python tooling; pip only re-runs when requirements.txt changes
$(VENV)/.installed: scripts/requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r scripts/requirements.txt
	touch $@

logs:            ## tail app logs
	kubectl -n secrets-sync logs -l app.kubernetes.io/instance=secrets-sync --all-containers --tail=50 -f

lint:            ## what CI runs (minus kubeconform)
	helm lint helm/secrets-sync
	helm template secrets-sync helm/secrets-sync -n secrets-sync >/dev/null
	shellcheck -x scripts/*.sh
	python3 -m py_compile helm/secrets-sync/files/app.py scripts/audit_secrets.py

reset:           ## delete everything and start over
	@./scripts/reset.sh
