# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is
Terraform (AzureRM 4.x) for a hybrid cloud reference architecture: a simulated on-prem VNet connected to an Azure landing zone (WAF → VM Scale Set → private app tier → private-endpoint SQL/Blob), plus Key Vault, monitoring, backup and budgets. Portfolio project, so readability and clean CI matter as much as features.

## Layout
- `infra/` is the root module. `main.tf` wires the modules; each module in `infra/modules/<name>/` has `main.tf`, `variables.tf`, `outputs.tf` and `versions.tf`.
- `infra/environments/*.tfvars` are the profiles: `lab` (default), `lowcost`, `full`. Expensive features stay behind boolean flags that default to **off**.
- `scripts/` has bootstrap (state), GitHub OIDC setup, and `validate-deployment.sh` (end-to-end tests).
- `.github/workflows/ci.yml` runs the quality gates; `deploy.yml` does a manual OIDC plan/apply/destroy.
- `app/fraud-detection/` is the Python API + Dockerfile; `deploy/helm/fraud-detection/` its Helm chart. `app.yml` tests, scans (Trivy, `.checkov-app.yaml`), deploys to kind, and publishes to GHCR; `deploy-app.yml` deploys the chart to AKS.
- `observability/` is the local Prometheus/Grafana lab (SLO rules + `promtool` tests); `monitoring/queries/` holds KQL; `finops/` the cost report; `docs/SRE.md` + `docs/runbooks/` the operations docs.

## Rules
- Run `make check` before committing (terraform fmt + validate, TFLint with `.tflint.hcl`, Checkov with `.checkov.yaml`). CI runs the same gates.
- App changes: `make app-test`; keep `observability/prometheus/tests.yml` in sync with alert rules; alert names and runbook links must match `docs/SRE.md`.
- Never add a Checkov skip without a comment in `.checkov.yaml` and a row in `docs/SECURITY.md`.
- Keep the address plan and ACL semantics in `docs/ARCHITECTURE.md` in sync with `modules/network` and `modules/onprem`.
- New paid resources need a feature flag (default false) and a line in the README cost table.
- Do not run `terraform apply` or `destroy` without asking the user first; they cost money.
- No secrets in code: generate them (random/tls providers) and store them in Key Vault.
- Use AzureRM 4.x argument names (e.g. `rbac_authorization_enabled`, `https_traffic_only_enabled`).
