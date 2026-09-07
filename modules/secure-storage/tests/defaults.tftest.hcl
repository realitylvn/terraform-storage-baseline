# The point of this file: prove the secure defaults hold when a consumer
# supplies only the three required inputs. A regression that flipped
# min_tls_version or re-enabled public blob access would pass
# `terraform validate` and fail here.
#
# ---------------------------------------------------------------------------
# Why mock_provider rather than a real azurerm provider block.
#
# The azurerm provider acquires an access token when it is CONFIGURED, before
# any resource is planned. So even at `command = plan`, a real provider block
# makes these tests require a live Azure credential — verified by running them
# against a bogus tenant, which failed at provider configuration with AADSTS90002
# and skipped all 22 runs.
#
# That would mean CI needs a credential, and this repository deliberately has no
# federated deploy identity (see REVIEW.md). mock_provider removes the provider
# entirely: no token, no network, no subscription.
#
# The trade is real and worth naming. These tests assert the module's own
# configuration logic, not the provider's behaviour, so they cannot catch a
# value the provider would reject. Two such bugs were in fact caught by running
# against the real provider during the build. Provider acceptance is therefore
# proved separately, by `terraform plan` on examples/complete against the live
# subscription — a workstation step, not a CI one.
# ---------------------------------------------------------------------------

mock_provider "azurerm" {}

variables {
  name                = "sttestbaselinedev01"
  resource_group_name = "rg-storage-baseline-test"
  location            = "eastus2"
}

run "transport_security_is_enforced" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "HTTPS-only transport was disabled. This is a fixed part of the baseline and must not be overridable."
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Default TLS floor regressed from TLS1_2."
  }
}

run "public_blob_access_is_disabled" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Anonymous public access to blobs and containers was permitted. This is a fixed part of the baseline."
  }
}

run "account_keys_are_disabled_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared access keys are enabled by default. The baseline requires Entra ID data-plane auth unless a consumer opts in."
  }
}

run "network_defaults_to_deny" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.this.network_rules) == 1
    error_message = "No network_rules block was emitted, so the account accepts traffic from anywhere."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Network default action is not Deny."
  }

  assert {
    condition     = contains(azurerm_storage_account.this.network_rules[0].bypass, "AzureServices")
    error_message = "AzureServices bypass missing; trusted Azure platform services would be blocked."
  }
}

run "encryption_and_data_protection_defaults" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true
    error_message = "Infrastructure (double) encryption at rest is off by default."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled == true
    error_message = "Blob versioning is off by default."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Blob soft-delete retention is not the 7-day default."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 7
    error_message = "Container soft-delete retention is not the 7-day default."
  }
}

# Versioning without lifecycle management is an unbounded cost-growth bug:
# every overwrite retains a billable previous version forever. Versioning being
# on by default is only safe because a pruning policy ships with it.
run "versioning_ships_with_a_pruning_policy" {
  command = plan

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 1
    error_message = "Blob versioning is enabled by default but no lifecycle management policy was created."
  }

  assert {
    condition     = azurerm_storage_management_policy.this[0].rule[0].actions[0].version[0].delete_after_days_since_creation == 90
    error_message = "Default policy does not prune previous blob versions at 90 days."
  }

  # "No deletion configured" has two representations: the real azurerm provider
  # normalises an unset day-count to the sentinel -1, while the mock leaves it
  # null. coalesce collapses both to a negative number. Comparing null with <=
  # is an error in Terraform, so this cannot be written as a bare inequality.
  assert {
    condition     = coalesce(azurerm_storage_management_policy.this[0].rule[0].actions[0].base_blob[0].delete_after_days_since_modification_greater_than, -1) <= 0
    error_message = "The default lifecycle rule deletes live base blobs. The default must tier data down, never delete it."
  }

  assert {
    condition     = azurerm_storage_management_policy.this[0].rule[0].actions[0].base_blob[0].tier_to_cool_after_days_since_modification_greater_than == 30
    error_message = "Default policy does not tier base blobs to cool at 30 days."
  }
}

run "system_assigned_identity_is_created" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.identity[0].type == "SystemAssigned"
    error_message = "No system-assigned identity; customer-managed keys would not be possible downstream."
  }
}
