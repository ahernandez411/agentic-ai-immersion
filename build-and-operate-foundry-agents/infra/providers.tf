terraform {
  required_version = ">= 1.12.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

provider "azurerm" {
  use_cli                         = true
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Authorization",
    "Microsoft.CognitiveServices",
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.DocumentDB",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Search",
    "Microsoft.Storage",
  ]
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    # Make destroy behavior explicit rather than relying on provider defaults:
    # fully purge Key Vaults on destroy (works now that purge_protection_enabled
    # is false), and recover a same-named soft-deleted vault on create instead
    # of erroring -- lets the deterministic key_vault_name survive a
    # destroy/apply cycle.
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azapi" {
  use_cli         = true
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
