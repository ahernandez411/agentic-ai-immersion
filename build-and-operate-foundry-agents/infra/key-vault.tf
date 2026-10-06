module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                          = local.key_vault_name
  location                      = module.resource_group.location
  resource_group_name           = module.resource_group.name
  tenant_id                     = var.tenant_id
  public_network_access_enabled = true
  # Purge protection intentionally off: this is a disposable workshop
  # environment, and purge protection cannot be turned back off on a vault
  # once it's been enabled (an Azure platform restriction) -- it would force
  # a 7-day soft-delete wait on every destroy, forever, for this vault name.
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  enable_telemetry           = false
  tags                       = local.tags

  role_assignments = {
    foundry_secrets = {
      role_definition_id_or_name       = "Key Vault Secrets User"
      principal_id                     = module.foundry_identity.principal_id
      principal_type                   = "ServicePrincipal"
      skip_service_principal_aad_check = true
    }
  }
}
