# Step-by-step deployment guide

This guide takes you from an empty laptop to:

1. the project on GitHub with a passing CI badge,
2. a real deployment in Azure,
3. automated tests proving that the design works,
4. one-click deploys from GitHub Actions,
5. everything torn down so you stop paying.

Plan for about **2 hours** the first time; most of it is waiting for Azure.

---

## Phase 0: Tools and accounts

| Need | Why | Get it |
|---|---|---|
| GitHub account | host the portfolio repo | github.com |
| Azure subscription | deploy target | Pay-as-you-go is easiest. Free/Student accounts work for the `lowcost` profile (see the quota note in Phase 3) |
| Git | version control | `winget install Git.Git` / `brew install git` |
| Azure CLI | log in to Azure, run scripts | `winget install Microsoft.AzureCLI` / `brew install azure-cli` |
| Terraform ≥ 1.6 | Infrastructure as Code | `winget install Hashicorp.Terraform` / `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| GitHub CLI | create the repo, set secrets | `winget install GitHub.cli` / `brew install gh` |
| make, bash | run the helpers | macOS/Linux have them; on Windows use **WSL** (`wsl --install`) or Git Bash |
| Claude Code | your AI pair-engineer in the terminal | see below |

**Install Claude Code** (needs a Claude Pro, Max, Team, Enterprise or Console account):

```bash
# macOS / Linux / WSL
curl -fsSL https://claude.ai/install.sh | bash
# Windows PowerShell
irm https://claude.ai/install.ps1 | iex
```

Check it works with `claude --version`. Run `claude` inside the project folder to start a session. Official setup docs: https://code.claude.com/docs/en/setup

> **Windows tip:** the scripts are bash. Do everything inside WSL (Ubuntu), and install `az`, `terraform`, `gh` and Claude Code inside WSL too.

---

## Phase 1: Get the code onto your machine

The project is already on GitHub at **https://github.com/SANJU-571/hybrid-cloud-migration-cicd-azure**.

```bash
gh auth login                                   # choose GitHub.com → HTTPS → browser
gh repo clone SANJU-571/hybrid-cloud-migration-cicd-azure
cd hybrid-cloud-migration-cicd-azure

# Description and topics shown under the repo name (one-time)
gh repo edit --description "Secure hybrid cloud for a bank on Azure: on-prem network linked to Azure via IPsec VPN, WAF-protected autoscaling web tier, private-endpoint SQL & Blob, Key Vault CMK, monitoring, backup. 100% Terraform, deployed by GitHub Actions (OIDC, approval gates), with automated security scans and network-segmentation tests."
gh repo edit --add-topic azure,terraform,hybrid-cloud,ci-cd,github-actions,devsecops,infrastructure-as-code,network-security,azure-networking
```

**Using Claude Code instead:** run `claude` in the folder and ask:

> *"Clone SANJU-571/hybrid-cloud-migration-cicd-azure, then set the repo description and topics listed in docs/DEPLOYMENT_GUIDE.md Phase 1."*

Claude Code shows each command and asks before running it.

---

## Phase 2: Watch CI go green (free, no Azure needed)

Open the **Actions** tab. The **CI** workflow runs four jobs:

| Job | What it proves |
|---|---|
| Terraform fmt & validate | the code is well-formed and type-correct against the real AzureRM provider |
| TFLint | best practices, plus Azure-specific checks such as invalid VM sizes and SKUs |
| Checkov | 80+ security policies, e.g. encryption, private endpoints, TLS 1.2 |
| ShellCheck | scripts are safe |

If a job is red, open it, copy the error, and in Claude Code say:

> *"The CI job 'Terraform fmt & validate' failed with: <paste>. Fix it, run the same check locally, and commit."*

---

## Phase 3: Prepare Azure

```bash
az login
az account set --subscription "<your subscription name or id>"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TF_VAR_alert_email="you@example.com"     # alerts + budget emails

# Register the resource providers this project uses (one-time, ~2 min)
for ns in Microsoft.Network Microsoft.Compute Microsoft.KeyVault Microsoft.Sql \
          Microsoft.Storage Microsoft.RecoveryServices Microsoft.Insights \
          Microsoft.OperationalInsights Microsoft.Cdn Microsoft.Security Microsoft.Consumption; do
  az provider register --namespace "$ns" --wait
done
```

**Quota check.** The `lab` profile runs 6 small VMs (6 vCPUs) and can autoscale to 8.

```bash
az vm list-usage -l canadacentral -o table | grep -Ei "Total Regional vCPUs|Standard BS Family"
```

If your limit is lower (free trials often allow only 4 vCPUs), either request an increase (Portal → *Quotas* → *Compute*), or deploy the `lowcost` profile after editing `infra/environments/lowcost.tfvars` to `web_instance_min = 1` and `web_instance_max = 2`. That's 5 vCPUs with the test VMs; set `deploy_onprem_test_vms = false` to get down to 2, at the cost of the ACL tests.

---

## Phase 4: Remote state (one time)

```bash
./scripts/bootstrap-tfstate.sh canadacentral
```

This creates `rg-nfb-tfstate` with a versioned storage account that uses Entra ID auth only, and writes `infra/backend.hcl`. That file is git-ignored; it is not a secret, but it is specific to your subscription.

---

## Phase 5: First deployment (from your laptop)

```bash
make init  PROFILE=lab
make plan  PROFILE=lab       # read the plan: ~90 resources, nothing gets deleted
make apply PROFILE=lab       # 15–25 minutes
```

What gets created is described in [ARCHITECTURE.md](ARCHITECTURE.md). When it finishes:

```bash
terraform -chdir=infra output
```

Open `portal_url` in a browser. Refresh a few times and the *Served by instance* value changes as the WAF load-balances across the scale set.

> **Want the real IPsec tunnel?** Set `connectivity_mode = "vpn"` in `environments/lab.tfvars` and run plan/apply again. VPN gateways take 30–45 minutes and cost about US$10/day more. Afterwards, Portal → *Connections* shows both tunnels as **Connected**.

> **Commit the lock file.** After the first `make init`, commit `infra/.terraform.lock.hcl`. It pins exact provider builds for repeatable deploys.

---

## Phase 6: Prove it works

```bash
make validate PROFILE=lab
```

The script tests the design the same way the capstone's *Testing & Validation* slide described:

| Test | Expected |
|---|---|
| Portal `/health` through the public entry | `200` |
| Requests spread over more than one VM Scale Set instance | yes |
| Web tier → private fraud-detection API | reachable |
| SQL-injection request | `403` from the WAF |
| **ACL 110**: Manager PC → Azure SQL private endpoint | OPEN |
| **ACL 110**: Employee PC → Azure SQL | CLOSED |
| **ACL 120**: Manager and Employee → on-prem DB | OPEN |
| **ACL 130 / 140**: Employee ↔ Manager VLANs | CLOSED |

The VLAN tests run inside the simulated on-prem VMs via `az vm run-command`, so they exercise real NSGs, routes and private DNS.

**Capture evidence for the README.** Recruiters look at screenshots. Save these to `docs/images/` and link them from the README:

1. the portal page in a browser,
2. the `make validate` output with every test passing,
3. Portal → resource group → **Resource visualizer**,
4. Portal → Application Gateway → **Backend health** (all healthy),
5. Log Analytics query `AzureDiagnostics | where Category == "ApplicationGatewayFirewallLog"` showing the blocked SQLi,
6. the green CI run, and the Deploy run waiting for approval.

Claude Code prompt:

> *"I added screenshots in docs/images. Add a 'Screenshots' section to README.md with captions, and commit."*

---

## Phase 7: Deploy from GitHub Actions (OIDC, no secrets)

```bash
./scripts/setup-github-oidc.sh "SANJU-571/hybrid-cloud-migration-cicd-azure" "you@example.com"
```

This script:
- creates an Entra ID app with **federated credentials** for your repo (no client secret exists anywhere),
- grants it `Contributor` and `Role Based Access Control Administrator` on the subscription, plus blob access to the state account,
- stores the IDs as GitHub secrets and variables,
- creates a `production` environment that requires **your approval**.

Then go to **Actions → Deploy → Run workflow** and run:
1. `action=plan`, `profile=lab`. Review the plan in the logs.
2. `action=apply`. Approve the run when GitHub asks. When it finishes, the outputs and test results appear in the run summary.

> If you already deployed from your laptop, the pipeline uses the same state file (`nfb-lab.tfstate`). It will only change the identity-specific settings: the Key Vault admin role assignment and the SQL Entra ID admin move to the pipeline's identity.

---

## Phase 8: Tear down (do this every time)

```bash
make destroy PROFILE=lab
# or: Actions → Deploy → action=destroy
```

The state storage account (`rg-nfb-tfstate`) costs cents per month; keep it for next time. Key Vaults stay soft-deleted for 7 days (free), and new deployments use new names.

**Budget safety net:** the deployment creates a monthly budget (US$150 in `lab`) that emails you at 50%, 80% and a forecast 100%.

---

## Phase 9: Present it

**Pin the repo** on your GitHub profile, and add the repo link plus one screenshot to LinkedIn and your résumé.

Talking points for interviews:
- *"I designed a hybrid cloud for a bank and implemented it on Azure entirely as Terraform: nine modules and about 90 resources, deployable in about 20 minutes and destroyable in one command."*
- *"The on-prem network is simulated as its own VNet, so I could prove the Cisco ACLs, now NSGs, from real VMs. For example, employees can't reach the cloud database but managers can."*
- *"There are no secrets in GitHub. The pipeline signs in with OIDC workload identity federation, and apply needs a manual approval."*
- *"Data services only have private endpoints. Storage is encrypted with an HSM-backed customer-managed key that rotates automatically."*
- *"I designed for cost. Feature flags switch off the expensive pieces (DDoS is about $2,950 a month), there's a log ingestion cap, and a budget alerts me."*
- *"Checkov runs on every push. Each check I skip is documented with a reason and the production fix."*

---

## Working on the project with Claude Code

The repo includes a [`CLAUDE.md`](../CLAUDE.md) that tells Claude Code how the project is laid out and which checks to run. Useful prompts:

| Goal | Prompt |
|---|---|
| Understand the code | *"Explain how traffic flows from the internet to the SQL database, and which NSG rules apply at each hop."* |
| Add HTTPS | *"Add an HTTPS listener to the Application Gateway using a self-signed certificate stored in Key Vault, and redirect HTTP to HTTPS. Keep Checkov passing."* |
| Add a feature | *"Add Azure Bastion behind a feature flag (default off) so I can SSH to the fraud VM without public IPs."* |
| Fix a failed apply | *"terraform apply failed with: <paste>. Diagnose and fix it."* |
| Cost check | *"Estimate the hourly cost of the lab profile, resource by resource."* |
| Interview prep | *"Ask me 10 interview questions about this architecture and grade my answers."* |

Claude Code asks before running commands. Review each `terraform apply` it proposes, because applies cost money.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `subscription ID could not be determined` | `export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)` |
| `AuthorizationFailed` creating role assignments | your account needs **Owner** or **User Access Administrator** on the subscription |
| `SkuNotAvailable` / quota errors | change `location` or `web_vm_size` in the tfvars, or request quota |
| Key Vault `403` right after creation | RBAC propagation is slow; run `make plan apply` again (the code already waits 90 s) |
| Portal returns 502 for the first few minutes | cloud-init is still installing nginx; wait about 5 minutes |
| `validate` fails on ACL tests in `vpn` mode | wait until both VPN connections show **Connected** |
| Destroy fails on the Recovery Services vault | Portal → vault → *Backup items* → stop backup and delete data, then destroy again |
