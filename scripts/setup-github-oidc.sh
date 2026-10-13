#!/usr/bin/env bash
# Wires GitHub Actions to Azure with OIDC workload identity federation
# (no client secrets), then stores the IDs as GitHub secrets/variables.
#
# Usage: ./scripts/setup-github-oidc.sh <github-owner>/<repo> <alert-email>
# Requires: az (logged in, Owner or User Access Administrator on the subscription),
#           gh (logged in with repo admin rights), infra/backend.hcl from bootstrap.
set -euo pipefail

REPO="${1:?usage: $0 <owner>/<repo> <alert-email>}"
ALERT_EMAIL="${2:?usage: $0 <owner>/<repo> <alert-email>}"
APP_NAME="gh-oidc-${REPO//\//-}"
BACKEND="$(dirname "$0")/../infra/backend.hcl"

[[ -f "$BACKEND" ]] || { echo "Run scripts/bootstrap-tfstate.sh first"; exit 1; }
TFSTATE_RG="$(sed -n 's/^resource_group_name *= *"\(.*\)"/\1/p' "$BACKEND")"
TFSTATE_SA="$(sed -n 's/^storage_account_name *= *"\(.*\)"/\1/p' "$BACKEND")"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo "==> Entra ID app registration: $APP_NAME"
APP_ID="$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi
SP_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)"
if [[ -z "$SP_ID" ]]; then
  SP_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
fi

echo "==> Federated credentials (main branch, environments, pull requests)"
add_cred() {
  local name="$1" subject="$2"
  if ! az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'] | [0].name" -o tsv | grep -q .; then
    az ad app federated-credential create --id "$APP_ID" --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$subject\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" -o none
  fi
}
add_cred "main"        "repo:${REPO}:ref:refs/heads/main"
add_cred "env-plan"    "repo:${REPO}:environment:plan"
add_cred "env-prod"    "repo:${REPO}:environment:production"
add_cred "pullrequest" "repo:${REPO}:pull_request"

echo "==> Azure RBAC for the pipeline identity"
assign() {
  az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
    --role "$1" --scope "$2" -o none 2>/dev/null || true
}
assign "Contributor" "/subscriptions/$SUB_ID"
# Needed because Terraform creates role assignments (Key Vault, storage CMK)
assign "Role Based Access Control Administrator" "/subscriptions/$SUB_ID"
assign "Storage Blob Data Contributor" \
  "$(az storage account show -n "$TFSTATE_SA" -g "$TFSTATE_RG" --query id -o tsv)"

echo "==> GitHub secrets & variables on $REPO"
gh secret set AZURE_CLIENT_ID --repo "$REPO" --body "$APP_ID"
gh secret set AZURE_TENANT_ID --repo "$REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUB_ID"
gh variable set TFSTATE_RESOURCE_GROUP --repo "$REPO" --body "$TFSTATE_RG"
gh variable set TFSTATE_STORAGE_ACCOUNT --repo "$REPO" --body "$TFSTATE_SA"
gh variable set ALERT_EMAIL --repo "$REPO" --body "$ALERT_EMAIL"

echo "==> GitHub environments (apply/destroy need your approval)"
MY_ID="$(gh api user --jq .id)"
gh api -X PUT "repos/$REPO/environments/plan" >/dev/null
gh api -X PUT "repos/$REPO/environments/production" \
  --input - >/dev/null <<EOF
{ "reviewers": [ { "type": "User", "id": $MY_ID } ] }
EOF

echo
echo "Done. Run the 'Deploy' workflow from the Actions tab (action=plan first)."
