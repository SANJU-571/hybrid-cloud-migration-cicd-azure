# Runbook: budget alert (50 % / 80 % / forecast 100 %)

**Alert:** Cost Management budget email for `rg-<prefix>-azure`
**Why it matters:** the lab is pay-as-you-go; the expensive pieces are behind feature flags.

## 1. Where is the money going?

Run the FinOps report (Actions → **FinOps** → Run workflow), or locally:

```bash
python3 finops/cost_report.py --prefix nfb-lab --budget 150
```

It shows month-to-date spend, the month-end forecast, cost by service and by `cost_center`, and waste (unattached disks, idle public IPs, VMs stopped but still allocated).

## 2. Act

| Finding | Action |
|---|---|
| Environment left running after a demo | `make destroy PROFILE=lab` (or Actions → Deploy → destroy) |
| Application Gateway / VPN gateways dominate | use the `lowcost` profile or `connectivity_mode = "peering"` for day-to-day work |
| AKS nodes | `enable_aks = false` when not demoing Kubernetes |
| Log Analytics ingestion | check [`log-ingestion-cost.kql`](../../monitoring/queries/log-ingestion-cost.kql); the workspace is capped at 1 GB/day |
| VMs "stopped" but still billed | deallocate (`az vm deallocate`), not just stop |

## 3. Close out

Forecast back under budget in the next report.
