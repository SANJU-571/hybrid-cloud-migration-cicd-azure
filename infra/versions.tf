terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # tls/time are used by child modules; pinned here so the whole
    # configuration resolves to one tested provider version.
    # tflint-ignore: terraform_unused_required_providers
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # tflint-ignore: terraform_unused_required_providers
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Remote state lives in an Azure Storage account created by
  # scripts/bootstrap-tfstate.sh. Values are supplied at init time:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # Purge protection is ON (required for customer-managed keys), so
      # destroyed vaults/keys stay soft-deleted for 7 days instead of being
      # purged. Names include a random suffix, so re-deploys never collide.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_keys_on_destroy    = false
      purge_soft_deleted_secrets_on_destroy = false
      recover_soft_deleted_key_vaults       = false
      recover_soft_deleted_keys             = false
      recover_soft_deleted_secrets          = false
    }
    storage {
      # Storage accounts are private-endpoint only; manage them purely via
      # Azure Resource Manager so CI runners never need data-plane access.
      data_plane_available = false
    }
    recovery_service {
      # Backup soft delete is always on in Azure; purge protected items so
      # `terraform destroy` can remove the vault in a lab.
      purge_protected_items_from_vault_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # subscription_id is read from ARM_SUBSCRIPTION_ID (set by az login
  # locally, or by the GitHub Actions OIDC workflow).
  storage_use_azuread = true
}
