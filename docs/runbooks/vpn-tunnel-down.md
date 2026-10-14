# Runbook: site-to-site VPN down (connectivity_mode = "vpn")

**Detected by:** `validate-deployment.sh` failing "Manager → cloud SQL", or on-prem users reporting they cannot reach Azure.
**Impact:** managers cannot reach the cloud database; the public portal is unaffected.

## 1. Confirm

```bash
PREFIX=nfb-lab
az network vpn-connection list -g rg-$PREFIX-azure --query '[].{name:name,status:connectionStatus}' -o table
az network vpn-connection list -g rg-$PREFIX-onprem-sim --query '[].{name:name,status:connectionStatus}' -o table
```

## 2. Mitigate

| Situation | Action |
|---|---|
| Status `Connecting` right after deploy | normal for up to ~10 min after the gateways finish |
| Status `NotConnected` | reset the gateway: `az network vnet-gateway reset -g rg-$PREFIX-azure -n vpngw-$PREFIX-azure` |
| Shared key / IPsec policy mismatch after an edit | re-apply Terraform so both sides get the same key and policy (IKEv2, AES-256, SHA-256, DH14, PFS2048) |
| Urgent access needed during the lab | temporarily switch `connectivity_mode = "peering"` and apply |

## 3. Close out

Both connections `Connected` and the ACL 110 test passes again.
