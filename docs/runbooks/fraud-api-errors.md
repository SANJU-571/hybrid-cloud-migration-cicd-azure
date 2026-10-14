# Runbook: fraud API errors, latency or down

**Alerts:** `FraudApiErrorBudgetFastBurn` (page), `FraudApiErrorBudgetSlowBurn`, `FraudApiLatencySLOBreach`, `FraudApiDown`
**Customer impact:** `/api/fraud/check` on the portal fails or is slow; transactions cannot be risk-scored. The portal home page is unaffected.

## 1. Confirm (2 min)

- Grafana *Fraud API - SLOs* (local) or Log Analytics: is the error ratio really above the budget line? Which route and status code?
- AKS: `kubectl -n fraud get pods -o wide` - restarts, `CrashLoopBackOff`, `Pending`?
- VM: `curl -s http://<portal>/api/fraud/check` from your laptop; `az vm get-instance-view -g rg-<prefix>-azure -n vm-<prefix>-fraud --query instanceView.statuses[1]`

## 2. Mitigate first

| Situation | Action |
|---|---|
| Started after a deploy | `helm rollback fraud-detection -n fraud` (AKS) - or redeploy the previous image tag with the *Deploy app (AKS)* workflow |
| Fault injection left on | `helm upgrade fraud-detection deploy/helm/fraud-detection -n fraud --reuse-values --set faults.errorRate=0 --set faults.latencyMs=0` |
| Pods `Pending` (no capacity) | check autoscaler events: `kubectl get events -n fraud --sort-by=.lastTimestamp`; raise `aks_node_max_count` |
| `OOMKilled` | raise `resources.limits.memory` in values and roll out |
| VM stopped / unhealthy | `az vm start` / `az vm restart -g rg-<prefix>-azure -n vm-<prefix>-fraud`; last resort: restore from Azure Backup |

## 3. Diagnose

- Logs: `kubectl -n fraud logs -l app.kubernetes.io/name=fraud-detection --tail=200` (JSON lines with route, status, duration_ms)
- Log Analytics: [`aks-pod-restarts.kql`](../../monitoring/queries/aks-pod-restarts.kql)
- NetworkPolicy/NSG: did the caller's IP range change? (`values-aks.yaml` `allowedCIDRs`, `nsg-…-app`)

## 4. Close out

SLI back above 99.5 % for 30 minutes → resolve → postmortem if it paged ([template](../postmortem-template.md)).
