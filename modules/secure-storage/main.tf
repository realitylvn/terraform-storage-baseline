# ---------------------------------------------------------------------------
# Secure-by-default Azure storage account.
#
# Two settings below are deliberately NOT variables. Overriding either one
# would mean this is no longer the baseline the module is named for:
#
#   https_traffic_only_enabled      = true
#   allow_nested_items_to_be_public = false
#
# Everything else is configurable, though several inputs are validated to
# refuse an insecure value (see variables.tf).
# ---------------------------------------------------------------------------

locals {
  # Azure rejects a management policy with zero rules; omit the resource
  # entirely when the consumer passes an empty list.
  emit_lifecycle_policy = length(var.lifecycle_rules) > 0
}

resource "azurerm_storage_account" "this" {
  # Checkov findings this module knowingly disagrees with. Each is a documented
  # decision from the design spec, not a silenced scanner. Skips are declared
  # inline so they appear in Checkov output as skipped-with-reason rather than
  # vanishing from the report.
  #
  # checkov:skip=CKV_AZURE_59:Public endpoint stays reachable by design; the control is a default-Deny firewall plus an explicit allowlist (see allowed_ip_ranges). Disabling the endpoint outright is a different product; documented in README as "firewall-restricted, not private".
  # checkov:skip=CKV_AZURE_206:LRS is the module default because this baseline optimises for cost; account_replication_type is a free variable and raising it to ZRS/GZRS is a one-line override, asserted by a test.
  # checkov:skip=CKV2_AZURE_1:Customer-managed keys need a Key Vault this standalone module has no business requiring. The module exposes a system-assigned identity precisely so CMK can be wired downstream.
  # checkov:skip=CKV2_AZURE_33:A private endpoint costs roughly $7.30/mo plus a VNet, subnet and Private DNS zone, breaking both the near-zero-cost and standalone constraints. Out of scope, stated in README.
  # checkov:skip=CKV_AZURE_33:Queue service logging is out of scope; this module provisions no queue service. Diagnostic settings need a Log Analytics workspace, which is a dependency and a recurring cost this module does not own.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = var.access_tier

  # --- Fixed baseline. Not variables, by design. ---
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # --- Validated-secure defaults. ---
  min_tls_version                   = var.min_tls_version
  shared_access_key_enabled         = var.shared_access_key_enabled
  public_network_access_enabled     = var.public_network_access_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled

  dynamic "identity" {
    for_each = var.identity_type == "None" ? [] : [1]
    content {
      type = var.identity_type
    }
  }

  blob_properties {
    versioning_enabled       = var.blob_versioning_enabled
    change_feed_enabled      = var.blob_change_feed_enabled
    last_access_time_enabled = var.blob_last_access_time_enabled

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }

  # Deliberately a static block rather than a `dynamic` one.
  #
  # It was dynamic at first, emitted only when it actually restricted
  # something, to avoid a no-op plan diff for default_action = "Allow". That
  # cosmetic gain cost more than it was worth twice over: static analysers
  # cannot evaluate a dynamic block, so Checkov reported CKV_AZURE_35 (default
  # network rule is deny) and CKV_AZURE_36 (trusted Microsoft services bypass)
  # as FAILING on an account that demonstrably had both applied; and the
  # attribute is computed when the block is absent, so tests could not assert
  # on it at plan time.
  #
  # Blinding a security scanner to the network control is a bad trade for a
  # tidier diff. Always emitting the block is also simply more honest: the
  # account always has a network rule set, whatever it is.
  network_rules {
    default_action             = var.network_default_action
    bypass                     = var.network_bypass
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  lifecycle {
    precondition {
      condition     = !(var.account_kind == "BlockBlobStorage" && var.account_tier != "Premium")
      error_message = "account_kind BlockBlobStorage requires account_tier Premium."
    }

    precondition {
      condition     = var.public_network_access_enabled || length(var.allowed_ip_ranges) == 0
      error_message = "allowed_ip_ranges has no effect while public_network_access_enabled is false. Enable the public endpoint or drop the IP allowlist."
    }
  }
}

# ---------------------------------------------------------------------------
# Containers.
#
# storage_account_id (not storage_account_name) routes creation through Azure
# Resource Manager rather than the storage data plane. That matters here:
# shared_access_key_enabled defaults to false, and the data-plane path would
# need an account key or a blob data role that Terraform may not hold yet.
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  # checkov:skip=CKV2_AZURE_21:Blob read logging needs a diagnostic setting pointed at a Log Analytics workspace. That is a dependency and a recurring cost this standalone module does not own; a consumer adds azurerm_monitor_diagnostic_setting against the module's `id` output.
  for_each = var.containers

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
  metadata           = each.value.metadata

  # Not a variable. A container on this baseline is private; public read access
  # is exactly what allow_nested_items_to_be_public = false forbids.
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Lifecycle management.
#
# Blob versioning without a lifecycle policy is an unbounded cost-growth bug:
# every overwrite retains a billable previous version indefinitely. The default
# rule tiers base blobs down but never deletes them, and prunes previous
# versions and snapshots at 90 days.
# ---------------------------------------------------------------------------

resource "azurerm_storage_management_policy" "this" {
  count = local.emit_lifecycle_policy ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      name    = rule.value.name
      enabled = rule.value.enabled

      filters {
        prefix_match = rule.value.prefix_match
        blob_types   = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.tier_to_cool_after_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.tier_to_archive_after_days
          delete_after_days_since_modification_greater_than          = rule.value.delete_after_days
        }

        dynamic "version" {
          for_each = rule.value.version_delete_after_days == null ? [] : [1]
          content {
            delete_after_days_since_creation = rule.value.version_delete_after_days
          }
        }

        # Not a typo, and not copy-paste drift from the version block above:
        # azurerm names this attribute delete_after_days_since_creation on
        # `version` but delete_after_days_since_creation_greater_than on
        # `snapshot`. The module absorbs that asymmetry so consumers pass one
        # consistent pair of variables.
        dynamic "snapshot" {
          for_each = rule.value.snapshot_delete_after_days == null ? [] : [1]
          content {
            delete_after_days_since_creation_greater_than = rule.value.snapshot_delete_after_days
          }
        }
      }
    }
  }
}
