locals {
  workload_name         = "${var.name_prefix}-${var.resource_suffix}"
  compact_workload_name = replace(local.workload_name, "-", "")
  resource_group_name   = "rg-${local.workload_name}"
  identity_name         = "id-${local.workload_name}"
  storage_account_name  = "st${local.compact_workload_name}"
  # Key Vault names are globally unique across every Azure tenant, so a
  # random suffix avoids collisions with other workshop attendees' vaults.
  # Truncate the base name first so the result never exceeds the 24-character
  # Key Vault name limit, regardless of name_prefix/resource_suffix length.
  key_vault_name               = "kv${substr(local.compact_workload_name, 0, 18)}${random_string.key_vault_suffix.result}"
  container_registry_name      = "cr${local.compact_workload_name}"
  foundry_account_name         = "ai-${local.workload_name}"
  foundry_project_name         = var.foundry_project_name
  search_service_name          = "srch-${local.workload_name}"
  cosmos_db_account_name       = "cosmos-${local.workload_name}"
  application_insights_name    = "appi-${local.workload_name}"
  log_analytics_workspace_name = "log-${local.workload_name}"

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
