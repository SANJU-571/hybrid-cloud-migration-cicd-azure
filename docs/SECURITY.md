# Security design and accepted lab risks

## Controls implemented

| Control | Where |
|---|---|
| No credentials in code or CI: GitHub → Azure via OIDC federation | `.github/workflows/deploy.yml`, `scripts/setup-github-oidc.sh` |
| Azure Backup soft delete always on (Azure secure-by-default); lab teardown purges protected items explicitly | `modules/backup`, provider features |
| Generated secrets (SSH key, SQL password) stored only in Key Vault, with 1-year expiry | `modules/security` |
| Key Vault: RBAC mode, purge protection, soft delete, audit logs to Log Analytics | `modules/security` |
| HSM-backed customer-managed key (RSA-HSM 3072) with automatic rotation encrypts Blob Storage; infrastructure double encryption | `modules/security`, `modules/data` |
| Azure SQL and Blob: **public network access disabled**, private endpoints + private DNS only; TLS 1.2 minimum; Entra ID admin; shared keys disabled on storage | `modules/data` |
| SQL auditing → Log Analytics (90 days) | `modules/data` |
| WAF_v2 in Prevention mode: OWASP CRS 3.2 + Bot Manager | `modules/compute` |
| No public IPs on any VM; SSH key auth only; Trusted Launch (Secure Boot + vTPM) | `modules/compute`, `modules/onprem` |
| Network segmentation: deny-all-inbound NSGs per tier, Cisco ACLs re-implemented | `modules/network`, `modules/onprem` |
| Controlled egress through a NAT Gateway; private subnets have no default outbound access | `modules/network` |
| IPsec policy: IKEv2, AES-256, SHA-256, DH group 14, PFS 2048 | `modules/connectivity` |
| Subscription Activity Log exported; email alert on any NSG rule change | `modules/monitoring` |
| Optional: DDoS Network Protection, Defender for Cloud (VMs, SQL, Storage, Key Vault) | flags in `variables.tf` |
| Policy as code: Checkov, TFLint, ShellCheck on every push; manual approval for apply/destroy | `.github/workflows/ci.yml` |

## Accepted risks in the lab profile

Each one is a skipped Checkov check (see `.checkov.yaml`). The table gives the production remediation.

| Risk | Why accepted in the lab | Production remediation |
|---|---|---|
| Key Vault data plane reachable from the internet (RBAC-protected) | GitHub-hosted runners have no fixed IPs | Private endpoint + self-hosted runners in the VNet; `public_network_access_enabled = false` |
| HTTP listener, no TLS on App Gateway | No custom domain or public certificate | HTTPS listener with a Key Vault certificate; HTTP→HTTPS redirect; Front Door managed certs |
| No encryption at host | Needs a subscription feature registration | `az feature register --namespace Microsoft.Compute --name EncryptionAtHost`, then enable on the VMs |
| Basic SQL tier: no zone redundancy or ledger | Cost (~US$5/month) | Business Critical / zone-redundant; ledger tables for transaction tamper-evidence |
| SQL vulnerability assessment via storage not configured | Defender for SQL covers it when enabled | `enable_defender_for_cloud = true` |
| VM extensions allowed | Needed for Backup, Run Command tests, health probes | Allow-list extensions with Azure Policy |

## Compliance mapping (indicative)

| PCI DSS v4 requirement | How this design helps |
|---|---|
| 1 – Network security controls | Tiered subnets, NSGs, WAF, no public IPs on servers |
| 3 – Protect stored account data | CMK encryption, private endpoints, TDE on Azure SQL (on by default) |
| 4 – Encrypt transmission | IPsec tunnel, TLS 1.2 minimum on data services |
| 7/8 – Restrict and authenticate access | Entra ID, RBAC, managed identities, SSH keys only |
| 10 – Log and monitor | Activity Log, Key Vault/SQL/WAF/Blob logs to Log Analytics, alerts |
| 11 – Test security regularly | Checkov on each change; segmentation tests in `validate-deployment.sh` |
| 12.10 – Incident response readiness | Backups with retention, alerting to the ops action group |
