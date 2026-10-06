locals {
  workload_name         = "${var.name_prefix}-${var.resource_suffix}"
  compact_workload_name = replace(local.workload_name, "-", "")
  resource_group_name   = "rg-${local.workload_name}-${random_string.unique_suffix.result}"
  # Storage, Key Vault, Container Registry, Foundry, AI Search, Cosmos DB, the
  # managed identity, and the resource group itself all share the same random
  # suffix for consistent naming across the deployment. For Storage/Key
  # Vault/ACR/Foundry/Search/Cosmos DB the suffix also avoids collisions with
  # other workshop attendees' deployments, since those names are globally
  # unique across every Azure tenant -- and, for Key Vault specifically, with
  # any still-lingering soft-deleted vault of your own from a previous
  # destroy cycle (recovering an old soft-deleted vault restores its original
  # purge-protection setting, not this config's value). The resource group
  # and managed identity names only need to be unique within the
  # subscription/resource group respectively, so neither strictly needs the
  # suffix, but both get one anyway for consistency.
  # Truncate the base name first so the result never exceeds each resource
  # type's name-length limit, regardless of name_prefix/resource_suffix length.
  identity_name           = "id-${local.workload_name}-${random_string.unique_suffix.result}"
  storage_account_name    = "st${substr(local.compact_workload_name, 0, 16)}${random_string.unique_suffix.result}"
  key_vault_name          = "kv${substr(local.compact_workload_name, 0, 16)}${random_string.unique_suffix.result}"
  container_registry_name = "cr${local.compact_workload_name}${random_string.unique_suffix.result}"
  foundry_account_name    = "ai-${local.workload_name}-${random_string.unique_suffix.result}"
  foundry_project_name    = "${var.foundry_project_name}-${random_string.unique_suffix.result}"
  search_service_name     = "srch-${local.workload_name}-${random_string.unique_suffix.result}"
  cosmos_db_account_name  = "cosmos-${local.workload_name}-${random_string.unique_suffix.result}"
  capability_host_name    = "${var.capability_host_name}-${random_string.unique_suffix.result}"

  model_deployments = {
    for key, deployment in var.model_deployments : key => {
      name                   = deployment.deployment_name
      version_upgrade_option = deployment.version_upgrade_option
      model = {
        format  = deployment.model_format
        name    = deployment.model_name
        version = deployment.model_version
      }
      scale = {
        capacity = deployment.capacity
        type     = deployment.sku_name
      }
    }
  }

  tags = merge({
    environment = var.environment
    managed-by  = "terraform"
    region      = var.location
    workload    = local.workload_name
  }, var.tags)
}

check "workshop_model_keys" {
  assert {
    condition     = contains(keys(var.model_deployments), var.chat_model_deployment_key)
    error_message = "chat_model_deployment_key must identify an entry in model_deployments."
  }

  assert {
    condition     = contains(keys(var.model_deployments), var.embedding_model_deployment_key)
    error_message = "embedding_model_deployment_key must identify an entry in model_deployments."
  }
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.resource_group_name
  location         = var.location
  enable_telemetry = false
  tags             = local.tags
}

resource "random_string" "unique_suffix" {
  length  = 6
  special = false
  upper   = false
}
