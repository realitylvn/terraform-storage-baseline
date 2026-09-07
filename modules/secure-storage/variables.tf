# ---------------------------------------------------------------------------
# Tier C — free variables. Identity and placement of the account.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Storage account name. Globally unique, 3-24 chars, lowercase alphanumeric only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 characters, lowercase letters and digits only (no hyphens)."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group to create the storage account in."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. eastus2."
  type        = string
}

variable "tags" {
  description = "Tags applied to the storage account."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Tier B — variables validated to refuse an insecure or unsupported value.
# ---------------------------------------------------------------------------

variable "min_tls_version" {
  description = <<-EOT
    Minimum TLS version for requests to the account.

    The variable exists so the floor can be raised, never lowered. TLS1_0 and
    TLS1_1 are refused on security grounds.

    TLS1_3 is also refused, but for a different reason: azurerm 4.81 accepts
    only TLS1_0, TLS1_1 and TLS1_2 for this field, so TLS1_3 fails inside the
    provider with a less obvious error. Refusing it here turns a confusing
    provider error into a clear one. When the provider adds TLS1_3, add it to
    the allowed set below -- nothing else needs to change.
  EOT
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_2"], var.min_tls_version)
    error_message = "min_tls_version must be TLS1_2. TLS1_0 and TLS1_1 are refused by this baseline; TLS1_3 is not yet accepted by the azurerm provider."
  }
}

variable "account_kind" {
  description = "Storage account kind. StorageV2 is the only kind supporting the full baseline (versioning, soft delete, lifecycle)."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage"], var.account_kind)
    error_message = "account_kind must be StorageV2 or BlockBlobStorage. Legacy Storage (v1) and BlobStorage do not support this baseline."
  }
}

variable "account_tier" {
  description = "Performance tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Replication strategy. LRS is the cheapest and the module default; raise it for production durability requirements."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Default access tier for blobs."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "blob_soft_delete_retention_days" {
  description = "Days to retain soft-deleted blobs. Azure permits 1-365."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "blob_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Days to retain soft-deleted containers. Azure permits 1-365."
  type        = number
  default     = 7

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "container_soft_delete_retention_days must be between 1 and 365."
  }
}

# ---------------------------------------------------------------------------
# Security posture. Defaults are the secure choice; consumers opt out.
# ---------------------------------------------------------------------------

variable "shared_access_key_enabled" {
  description = <<-EOT
    Whether the account's shared access keys are usable.

    Defaults to false: callers authenticate with Entra ID and hold a data-plane
    role. Note that a control-plane role (Contributor, Storage Account
    Contributor) grants NO data-plane access — that is a separate role such as
    Storage Blob Data Reader/Contributor. Set true only when a consumer needs
    connection-string access.
  EOT
  type        = bool
  default     = false
}

variable "infrastructure_encryption_enabled" {
  description = "Enable a second layer of encryption at rest. Free, but immutable after creation."
  type        = bool
  default     = true
}

variable "identity_type" {
  description = "Managed identity for the account. A system-assigned identity costs nothing and is a prerequisite for customer-managed keys later."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "None"], var.identity_type)
    error_message = "identity_type must be SystemAssigned or None."
  }
}

# ---------------------------------------------------------------------------
# Network. Public endpoint reachable, but denied by default (see D2 in the
# design spec). This is firewall-restricted, not private.
# ---------------------------------------------------------------------------

variable "public_network_access_enabled" {
  description = "Whether the public endpoint resolves at all. Left true because the allowlist below, not endpoint removal, is this baseline's network control."
  type        = bool
  default     = true
}

variable "network_default_action" {
  description = "Action for traffic matching no rule below. Deny is the baseline."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be Allow or Deny."
  }
}

variable "network_bypass" {
  description = "Azure platform traffic exempt from the firewall."
  type        = set(string)
  default     = ["AzureServices"]

  validation {
    condition     = alltrue([for b in var.network_bypass : contains(["AzureServices", "Logging", "Metrics", "None"], b)])
    error_message = "network_bypass entries must be from AzureServices, Logging, Metrics, None."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    Public IPv4 addresses or CIDR ranges permitted through the firewall.

    Azure rejects RFC1918 private ranges here, and rejects /31 and /32 prefixes
    — supply a bare address rather than x.x.x.x/32.
  EOT
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet resource IDs permitted via a service endpoint."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Data protection and lifecycle.
# ---------------------------------------------------------------------------

variable "blob_versioning_enabled" {
  description = "Retain previous versions of a blob on overwrite. Note the cost implication: without the lifecycle policy below, retained versions grow without bound."
  type        = bool
  default     = true
}

variable "blob_change_feed_enabled" {
  description = "Record an ordered log of blob changes. Off by default — it is an auditing feature with its own storage cost."
  type        = bool
  default     = false
}

variable "blob_last_access_time_enabled" {
  description = "Track blob last-access time. Required for lifecycle rules keyed on last access rather than last modification."
  type        = bool
  default     = false
}

variable "containers" {
  description = "Blob containers to create. Keys are container names; access_type is forced to private by the baseline."
  type = map(object({
    metadata = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for n in keys(var.containers) : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", n))])
    error_message = "Container names must be 3-63 chars, lowercase alphanumeric or hyphen, and start and end with a letter or digit."
  }
}

variable "lifecycle_rules" {
  description = <<-EOT
    Blob lifecycle management rules.

    The default is deliberately safe rather than aggressive: base blobs are
    tiered down but NEVER deleted, while previous versions and snapshots are
    deleted at 90 days. That bounds the cost that blob versioning introduces
    without ever removing live data. Set to [] to create no management policy.
  EOT
  type = list(object({
    name                       = string
    enabled                    = optional(bool, true)
    prefix_match               = optional(list(string), [])
    tier_to_cool_after_days    = optional(number)
    tier_to_archive_after_days = optional(number)
    delete_after_days          = optional(number)
    version_delete_after_days  = optional(number)
    snapshot_delete_after_days = optional(number)
  }))

  default = [{
    name                       = "baseline-tier-and-prune"
    enabled                    = true
    tier_to_cool_after_days    = 30
    tier_to_archive_after_days = 90
    delete_after_days          = null
    version_delete_after_days  = 90
    snapshot_delete_after_days = 90
  }]
}
