#!/usr/bin/env bash
# Creates the Azure Storage account that holds Terraform remote state.
# Run once per subscription:   ./scripts/bootstrap-tfstate.sh [location]
set -euo pipefail

LOCATION="${1:-canadacentral}"
RG="rg-nfb-tfstate"
CONTAINER="tfstate"

command -v az >/dev/null || { echo "Azure CLI (az) is required"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Run 'az login' first"; exit 1; }

SUB_ID="$(az account show --query id -o tsv)"
ME="$(az ad signed-in-user show --query id -o tsv)"

echo "Subscription : $(az account show --query name -o tsv) ($SUB_ID)"
echo "Location     : $LOCATION"

az group create -n "$RG" -l "$LOCATION" --tags project=n-financial-bank-hybrid-cloud purpose=terraform-state -o none

# Re-use an existing state account if this script was run before
SA="$(az storage account list -g "$RG" --query "[0].name" -o tsv)"
if [[ -z "$SA" ]]; then
  SA="sttfstate$(openssl rand -hex 4)"
  echo "Creating storage account $SA ..."
  az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
    --sku Standard_GRS --kind StorageV2 \
    --min-tls-version TLS1_2 --https-only true \
    --allow-blob-public-access false \
    --allow-shared-key-access false -o none
fi

SA_ID="$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)"

az storage account blob-service-properties update --account-name "$SA" -g "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 -o none

# Entra ID auth only (no account keys) -> give yourself data-plane access
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none 2>/dev/null || true

echo "Waiting for role assignment to propagate..."
for _ in $(seq 1 12); do
  if az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none 2>/dev/null; then
    break
  fi
  sleep 10
done

cat > "$(dirname "$0")/../infra/backend.hcl" <<EOF
resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "$CONTAINER"
key                  = "nfb-lab.tfstate"
use_azuread_auth     = true
EOF

echo
echo "Done. Backend config written to infra/backend.hcl"
echo "  TFSTATE_RESOURCE_GROUP  = $RG"
echo "  TFSTATE_STORAGE_ACCOUNT = $SA"
