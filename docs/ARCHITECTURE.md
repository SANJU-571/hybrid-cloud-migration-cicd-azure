# Architecture

## Design goals (from the capstone brief)

N-Financial Bank must modernise its legacy on-premises estate **gradually**: core systems and regulatory constraints rule out a big-bang migration. The target is a **hybrid cloud**. On-prem keeps the legacy systems; Azure hosts re-architected microservices, joined by an encrypted link and governed by the same segmentation rules the on-prem network already enforces. The design must meet PCI DSS and GDPR expectations: segmentation, encryption, least privilege, audit trail, backup.

## Logical view

| Layer | On-premises (simulated) | Azure |
|---|---|---|
| Edge | — | Front Door *(opt.)* → Application Gateway WAF_v2 (or Standard LB) |
| Presentation | Core banking server | VM Scale Set: customer portal (nginx), zones 1–3 |
| Application | — | Fraud-detection API (private VM, :8080) |
| Data | On-prem DB server | Azure SQL Database + Blob Storage via private endpoints |
| Users | Manager VLAN 30, Employee VLAN 40 | — |
| Connectivity | VPN device | VPN Gateway (IPsec S2S) *or* VNet peering |
| Platform | — | Key Vault, Log Analytics, Azure Monitor, Recovery Services vault, NAT Gateway |

## Address plan

The IP plan copies the Cisco Packet Tracer lab, so the original ACL slide still reads correctly.

| Network | CIDR | Purpose |
|---|---|---|
| **Azure VNet** | 192.168.200.0/21 | |
| GatewaySubnet | 192.168.200.0/27 | VPN Gateway (name required by Azure) |
| AppGatewaySubnet | 192.168.201.0/24 | Application Gateway WAF_v2 |
| snet-web | 192.168.202.0/24 | Customer-portal VM Scale Set |
| snet-data | 192.168.203.0/24 | Private endpoints: SQL, Blob |
| snet-app | 192.168.204.0/24 | Fraud-detection VM (192.168.204.10) |
| **On-prem VNet** | 192.168.0.0/17 | |
| snet-managers | 192.168.30.0/24 | VLAN 30 (Manager PC 192.168.30.10) |
| snet-employees | 192.168.40.0/24 | VLAN 40 (Employee PC 192.168.40.10) |
| snet-core-banking | 192.168.101.0/24 | Core banking server |
| snet-onprem-db | 192.168.102.0/24 | On-prem DB (stand-in listener 192.168.102.10:1433) |
| GatewaySubnet | 192.168.120.0/27 | On-prem VPN device |

## From Cisco ACLs to NSGs

| Capstone ACL | Intent | Azure enforcement |
|---|---|---|
| **ACL 110** | Only the Manager VLAN may reach the cloud DB | `nsg-…-data`: allow 192.168.30.0/24 → 1433; deny 192.168.40.0/24; deny all. Private-endpoint network policies are **enabled**, so the NSG applies to the SQL private endpoint |
| (note) | Employees cannot access cloud resources | `nsg-…-onprem-employees` outbound deny → 192.168.200.0/21 |
| **ACL 120** | Employees + Managers → on-prem DB only | `nsg-…-onprem-onprem-db`: allow both VLANs on 1433; deny all |
| **ACL 130** | Employee VLAN must not reach Manager VLAN | `nsg-…-onprem-managers`: deny inbound from 192.168.40.0/24 |
| **ACL 140** | Manager VLAN must not reach Employee VLAN | `nsg-…-onprem-employees`: deny inbound from 192.168.30.0/24 |
| — | Tiering inside Azure | web accepts :80 only from the App Gateway subnet; app accepts :8080 only from web; data accepts :1433/:443 only from app/web/managers |

`scripts/validate-deployment.sh` checks every row above from real VMs.

## Key traffic flows

1. **Customer request:** Internet → (Front Door) → App Gateway public IP → WAF (OWASP 3.2, Prevention) → VMSS instance in a healthy zone → response.
2. **East-west:** VMSS → `192.168.204.10:8080` fraud-detection API (NSG-restricted).
3. **Manager → cloud DB:** 192.168.30.10 → VPN tunnel (or peering) → resolves `sql-….database.windows.net` via the linked private DNS zone → 192.168.203.x private endpoint → allowed by ACL 110.
4. **Employee → cloud DB:** blocked twice, by the outbound NSG on the employee subnet and the inbound NSG on the data subnet.
5. **Egress:** web and app tiers reach the internet only through the NAT Gateway (fixed IP, no implicit outbound access). The data and on-prem subnets have no egress.

## High availability and DR

| Concern | Mechanism |
|---|---|
| Zone failure | VMSS and App Gateway span zones 1–3; Standard public IPs are zone-redundant |
| Instance failure | Application Health extension + automatic instance repair; WAF probe removes unhealthy backends |
| Load | Autoscale +1 at CPU > 70 % (5 min), −1 at < 25 % (10 min), 2–4 instances (`lab`) |
| Bad release | Rolling upgrade policy: 50 % batches, 30 s pause, abort on unhealthy instances |
| Data loss | SQL point-in-time restore (7 days); blob versioning, soft delete (14 days), GRS/GZRS |
| Server loss | Azure Backup of the fraud-detection VM: daily, 7 daily / 4 weekly / 12 monthly points; optional geo-redundant vault with cross-region restore |
| On-prem resilience | (out of scope for IaC) RAID, failover clusters and UPS, as in the capstone |

## Deployment strategies (capstone slide 6)

| Strategy | How to do it here |
|---|---|
| Rolling update | built in: change the image or cloud-init, `terraform apply`, and the VMSS rolls in 50 % batches gated by health |
| Blue-green | deploy a second profile (e.g. `environment = "green"`), smoke-test it, then switch Front Door's origin or the DNS |
| Green (cloud-only new feature) | new services land only in Azure; on-prem stays as the safety net, reachable over the tunnel |
