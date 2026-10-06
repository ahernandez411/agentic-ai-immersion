resource "azurerm_log_analytics_workspace" "foundry" {
  name                       = local.log_analytics_workspace_name
  location                   = module.resource_group.location
  resource_group_name        = module.resource_group.name
  sku                        = "PerGB2018"
  retention_in_days          = var.log_analytics_retention_in_days
  internet_ingestion_enabled = true
  internet_query_enabled     = true
  tags                       = local.tags
}
