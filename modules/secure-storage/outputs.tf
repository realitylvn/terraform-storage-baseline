output "id" {
  description = "Resource ID of the storage account. Use this as the scope for a data-plane role assignment."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_blob_host" {
  description = "Primary blob service host, without scheme."
  value       = azurerm_storage_account.this.primary_blob_host
}

output "identity_principal_id" {
  description = "Object ID of the account's system-assigned managed identity, or null when identity_type is None."
  value       = var.identity_type == "None" ? null : one(azurerm_storage_account.this.identity[*].principal_id)
}

output "container_names" {
  description = "Names of the containers created by this module."
  value       = sort(keys(azurerm_storage_container.this))
}

output "security_posture" {
  description = "The controls this module actually applied. Emitted so a consumer, a test, or a reviewer can assert on the baseline rather than trusting the documentation."
  value = {
    https_traffic_only_enabled        = azurerm_storage_account.this.https_traffic_only_enabled
    min_tls_version                   = azurerm_storage_account.this.min_tls_version
    allow_nested_items_to_be_public   = azurerm_storage_account.this.allow_nested_items_to_be_public
    shared_access_key_enabled         = azurerm_storage_account.this.shared_access_key_enabled
    public_network_access_enabled     = azurerm_storage_account.this.public_network_access_enabled
    infrastructure_encryption_enabled = azurerm_storage_account.this.infrastructure_encryption_enabled
    network_default_action            = azurerm_storage_account.this.network_rules[0].default_action
    blob_versioning_enabled           = var.blob_versioning_enabled
    lifecycle_policy_applied          = local.emit_lifecycle_policy
  }
}
