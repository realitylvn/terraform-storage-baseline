output "resource_group_name" {
  description = "Resource group created by this example."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Name of the storage account created by the module."
  value       = module.storage.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint. Reachable only from allowed_ip_ranges, and only with an Entra ID token."
  value       = module.storage.primary_blob_endpoint
}

output "container_names" {
  description = "Containers created by the module."
  value       = module.storage.container_names
}

output "security_posture" {
  description = "Controls the module actually applied, as reported by the provider rather than by the documentation."
  value       = module.storage.security_posture
}

output "verify_commands" {
  description = "Copy-paste az commands to independently confirm the baseline after apply, without trusting Terraform state."
  value = {
    security_settings = "az storage account show --name ${module.storage.name} --resource-group ${azurerm_resource_group.this.name} --query \"{httpsOnly:supportsHttpsTrafficOnly, minTls:minimumTlsVersion, publicBlob:allowBlobPublicAccess, sharedKey:allowSharedKeyAccess, netDefault:networkRuleSet.defaultAction, infraEncryption:encryption.requireInfrastructureEncryption}\" -o table"
    blob_properties   = "az storage account blob-service-properties show --account-name ${module.storage.name} --resource-group ${azurerm_resource_group.this.name} --query \"{versioning:isVersioningEnabled, blobSoftDelete:deleteRetentionPolicy.days, containerSoftDelete:containerDeleteRetentionPolicy.days}\" -o table"
    lifecycle_policy  = "az storage account management-policy show --account-name ${module.storage.name} --resource-group ${azurerm_resource_group.this.name} --query \"policy.rules\" -o json"
    list_containers   = "az storage container list --account-name ${module.storage.name} --auth-mode login -o table"
  }
}
