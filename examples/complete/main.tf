# ---------------------------------------------------------------------------
# Example root module.
#
# Creates a resource group, consumes the secure-storage module, and grants the
# caller the data-plane role the module's own defaults make necessary.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

# Storage account names are globally unique across all of Azure, so a
# deterministic name collides with any other tenant that picked it. The suffix
# is keyed to the resource group so repeated applies are stable, and a destroy
# followed by an apply reuses the name rather than leaking abandoned accounts.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    resource_group = var.resource_group_name
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "storage" {
  source = "../../modules/secure-storage"

  name                = "${var.name_prefix}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  # Everything below is left at the module default on purpose — the example
  # demonstrates that the baseline needs no configuration to be secure. The
  # only input given is the firewall allowlist, which cannot have a safe
  # default because it is specific to the operator.
  allowed_ip_ranges = var.allowed_ip_ranges

  containers = {
    "artifacts" = {}
    "logs"      = { metadata = { purpose = "example" } }
  }
}

# ---------------------------------------------------------------------------
# Data-plane access.
#
# This assignment is the direct consequence of the module disabling shared
# access keys. Without it the account exists and is completely unusable, which
# is the correct failure mode: access is granted deliberately, not inherited.
#
# The distinction that matters: a CONTROL-plane role (Owner, Contributor,
# Storage Account Contributor) lets a principal manage the account resource and
# grants it nothing whatsoever on the blob data inside. Reading a blob needs a
# DATA-plane role. Conflating the two produces a 403 against a valid token —
# the bug that cost azure-drift-detector a checkpoint.
#
# Scope is the storage account, not the resource group. The resource group is a
# ceiling, not a default.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "caller_blob_data" {
  count = var.assign_data_plane_role ? 1 : 0

  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  # Set explicitly so the assignment does not fail on Entra replication lag.
  principal_type = "User"
}
