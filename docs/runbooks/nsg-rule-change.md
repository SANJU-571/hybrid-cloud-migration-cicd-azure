# Runbook: NSG rule changed

**Alert:** Activity Log alert *A Network Security Group rule was created, changed or deleted*
**Why it matters:** NSGs implement the bank's segmentation (Cisco ACLs 110–140). An out-of-band change can expose the data tier.

## 1. Who changed what?

```kusto
AzureActivity
| where TimeGenerated > ago(1h)
| where OperationNameValue =~ "Microsoft.Network/networkSecurityGroups/securityRules/write"
| project TimeGenerated, Caller, ResourceGroup, _ResourceId, ActivityStatusValue, Properties
```

## 2. Decide

| Caller | Action |
|---|---|
| The pipeline identity during an approved *Deploy* run | Expected; close. |
| A person or unknown identity | Treat as a security incident: run `terraform plan` to see drift, then `terraform apply` to restore the reviewed rules, and run `validate-deployment.sh` to re-prove segmentation. |

## 3. Close out

`terraform plan` shows no NSG drift and the ACL tests pass. Record the caller and reason.
