terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.60, < 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12"
    }
  }
}
