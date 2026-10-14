# Local workflow. Usage: make plan PROFILE=lab   (profiles: lab | lowcost | full)
PROFILE ?= lab
TF       = terraform -chdir=infra
VARFILE  = -var-file=environments/$(PROFILE).tfvars

export ARM_SUBSCRIPTION_ID ?= $(shell az account show --query id -o tsv 2>/dev/null)

.PHONY: help bootstrap init plan apply destroy validate fmt lint scan check app-test app-lab app-lab-down cost-report game-day

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

bootstrap: ## Create the remote-state storage account (once)
	./scripts/bootstrap-tfstate.sh

init: ## terraform init against the remote state for PROFILE
	$(TF) init -backend-config=backend.hcl -backend-config=key=nfb-$(PROFILE).tfstate -reconfigure

plan: ## terraform plan for PROFILE
	$(TF) plan $(VARFILE) -out=tfplan

apply: ## Apply the last plan
	$(TF) apply tfplan

destroy: ## Destroy everything in PROFILE (stop the billing!)
	$(TF) destroy $(VARFILE)

validate: ## Run end-to-end tests against the deployed PROFILE
	./scripts/validate-deployment.sh nfb-$(PROFILE)

fmt: ## Format Terraform
	terraform fmt -recursive infra

lint: ## TFLint
	tflint --init --config "$(CURDIR)/.tflint.hcl" && cd infra && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

scan: ## Checkov security scan
	checkov --config-file .checkov.yaml

check: fmt lint scan ## All local quality gates
	$(TF) init -backend=false -input=false >/dev/null && $(TF) validate

app-test: ## Unit tests for the fraud API and the FinOps report
	python3 -m pytest -q app/fraud-detection/tests finops/tests

app-lab: ## Local API + Prometheus + Grafana (http://localhost:3000)
	cd observability && docker compose up -d --build

app-lab-down: ## Stop the local observability lab
	cd observability && docker compose down -v

cost-report: ## FinOps report for PROFILE (needs az login)
	python3 finops/cost_report.py --prefix nfb-$(PROFILE) --budget $(or $(BUDGET),150)

game-day: ## Fault-injection game day: make game-day EXPERIMENT=web-instance|fraud-vm
	./scripts/game-day.sh nfb-$(PROFILE) $(or $(EXPERIMENT),web-instance)
