# Runbook: customer portal unhealthy or saturated

**Alerts:** App Gateway unhealthy backend hosts (sev 1), web tier CPU > 85 % (sev 2)
**Customer impact:** portal 502/504s or slow pages if every backend is unhealthy or saturated.

## 1. Confirm

```bash
PREFIX=nfb-lab
az network application-gateway show-backend-health -g rg-$PREFIX-azure -n agw-$PREFIX \
  --query 'backendAddressPools[].backendHttpSettingsCollection[].servers[].{ip:address,health:health}' -o table
az vmss list-instances -g rg-$PREFIX-azure -n vmss-$PREFIX-web -o table
```

Run [`portal-availability-burn-rate.kql`](../../monitoring/queries/portal-availability-burn-rate.kql) to see whether customers are actually failing (SLI) or only one instance is.

## 2. Mitigate

| Situation | Action |
|---|---|
| One instance unhealthy, others fine | No customer impact; automatic instance repair replaces it after the grace period. To speed up: `az vmss reimage --instance-ids <id>` |
| All instances unhealthy after a change | Roll back the cloud-init/image change and `terraform apply`; the rolling upgrade policy stops bad batches |
| CPU saturated at max instances | Raise `web_instance_max` (and quota) or `web_vm_size`; check for abusive traffic in [`waf-blocked-requests.kql`](../../monitoring/queries/waf-blocked-requests.kql) |
| nginx not answering on a new instance | cloud-init still running (first ~5 min) - wait, then check `/var/log/cloud-init-output.log` via `az vmss run-command` |

## 3. Close out

Unhealthy-host count back to 0 and availability SLI above 99.5 % → resolve.
