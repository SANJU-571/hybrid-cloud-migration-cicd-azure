# Site reliability: SLOs, alerting and incident response

This page defines how "working" is measured for the two customer-facing paths, what wakes someone up, and how incidents are run and learned from.

## Service level objectives

| Service | SLI (what is measured) | SLO (30-day window) | Error budget | Source |
|---|---|---|---|---|
| Customer portal | Share of requests through Application Gateway that are **not 5xx** (health probes excluded) | **99.5 %** | 0.5 % ≈ 3 h 36 min/month | App Gateway access logs → [`portal-availability-slo.kql`](../monitoring/queries/portal-availability-slo.kql) |
| Customer portal | Share of requests answered in **< 1 s** | 95 % | 5 % | [`portal-latency-p95.kql`](../monitoring/queries/portal-latency-p95.kql) |
| Fraud-detection API | Share of `/v1/score` and `/check` requests that are **not 5xx** | **99.5 %** | 0.5 % | Prometheus `http_requests_total` → `slo:sli_error:ratio_rate*` ([rules](../observability/prometheus/rules.yml)) |
| Fraud-detection API | Share of scoring requests faster than **300 ms** (p95 < 300 ms) | 95 % | 5 % | `http_request_duration_seconds` histogram |

**Why 99.5 % and not 99.99 %?** The lab runs on single-region, cost-optimised SKUs (Free AKS tier, Basic SQL, B-series VMs). 99.5 % is achievable with zone-redundant scale sets and honest about what the platform can deliver; a production bank would move to 99.9 %+ with paid SLAs and a second region.

## Alerting: page on symptoms, not causes

Alerts use **multi-window, multi-burn-rate** rules (Google SRE Workbook, ch. 5) so a short blip does not page but a real outage pages within minutes.

| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| `FraudApiErrorBudgetFastBurn` | error ratio > 14.4 × budget over **1 h and 5 m** (2 % of the monthly budget in an hour) | page | [fraud-api-errors](runbooks/fraud-api-errors.md) |
| `FraudApiErrorBudgetSlowBurn` | error ratio > 6 × budget over **6 h and 30 m** | ticket | [fraud-api-errors](runbooks/fraud-api-errors.md) |
| `FraudApiLatencySLOBreach` | p95 > 300 ms for 10 m | ticket | [fraud-api-errors](runbooks/fraud-api-errors.md) |
| `FraudApiDown` | scrape target down for 1 m | page | [fraud-api-errors](runbooks/fraud-api-errors.md) |
| App Gateway unhealthy hosts (Azure Monitor) | unhealthy backend count > 0 for 5 m | sev 1 | [portal-unhealthy](runbooks/portal-unhealthy.md) |
| Web tier CPU > 85 % (Azure Monitor) | 15 m average | sev 2 | [portal-unhealthy](runbooks/portal-unhealthy.md) |
| NSG rule changed (Activity Log) | any `securityRules/write` | security | [nsg-rule-change](runbooks/nsg-rule-change.md) |
| Budget 50 / 80 / 100 % (Cost Management) | actual / forecast spend | cost | [budget-alert](runbooks/budget-alert.md) |
| VPN tunnel down (vpn mode) | no metric alert in the lab; detected by `validate-deployment.sh` (manager → cloud SQL fails) or a user report | sev 1 | [vpn-tunnel-down](runbooks/vpn-tunnel-down.md) |

The Prometheus rules have **unit tests** ([`tests.yml`](../observability/prometheus/tests.yml)) that run in CI with `promtool test rules`: a 50 % error rate must page, a 0.1 % error rate must not.

## Error budget policy

| Budget left (30 days) | What happens |
|---|---|
| > 50 % | Normal delivery. Risky changes allowed with a rollback plan. |
| 25–50 % | Releases need a passing game day for the affected path. |
| < 25 % | Feature work pauses; only reliability fixes and security patches ship. |
| Exhausted | Freeze until the budget recovers; a postmortem is mandatory for the top contributor. |

## Reliability mechanisms already in the design

| Failure | Mechanism | Verified by |
|---|---|---|
| A web instance dies | App Gateway health probe drains it; VMSS automatic repair replaces it | `scripts/game-day.sh <prefix> web-instance` |
| A zone fails | VMSS, App Gateway and AKS nodes span zones 1–3 | design review |
| A bad release | VMSS rolling upgrades abort on unhealthy instances; Helm `--atomic` rolls back; Kubernetes `maxUnavailable: 0` + readiness probes + preStop drain | CI "Zero-downtime rolling update" step on kind (fails on a single failed request) |
| A pod is killed or a node drains | 2+ replicas, PodDisruptionBudget, topology spread across zones/nodes, HPA | kind CI + AKS |
| The fraud API breaks | Portal stays up; only `/api/fraud/check` fails (dependency isolated) | `scripts/game-day.sh <prefix> fraud-vm` |
| Data loss | SQL PITR, blob versioning/soft delete, Azure Backup | restore drill (Portal → vault → Restore) |

## Practise it locally (free)

```bash
cd observability
docker compose up -d --build              # Grafana http://localhost:3000 · Prometheus http://localhost:9090
FAULT_ERROR_RATE=0.2 docker compose up -d fraud-api   # inject 20 % errors
# within ~3 minutes FraudApiErrorBudgetFastBurn fires (Prometheus → Alerts) and
# the Grafana "Fraud API - SLOs" dashboard shows the budget draining
docker compose up -d fraud-api            # recover (FAULT_ERROR_RATE unset)
docker compose down -v
```

`FAULT_LATENCY_MS=500` does the same for the latency SLO. On Kubernetes the same switches are Helm values: `--set faults.errorRate=0.2`.

## Incident process

1. **Detect**: an alert fires with a runbook link.
2. **Respond**: the on-call engineer acknowledges, opens an incident channel/issue, and follows the runbook. Mitigate first (roll back, scale out, fail over), then diagnose.
3. **Communicate**: status update every 30 minutes while customer impact lasts.
4. **Recover**: confirm the SLI is back above target on the dashboard/KQL query.
5. **Learn**: a blameless postmortem within 5 working days for any page, using the [template](postmortem-template.md). Action items become GitHub issues.
