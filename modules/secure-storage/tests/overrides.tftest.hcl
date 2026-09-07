# The point of this file: the baseline is a default, not a cage. Prove that a
# consumer with a real reason can opt out of the soft controls — and that the
# two hard controls stay put regardless.

mock_provider "azurerm" {}

variables {
  name                = "sttestbaselinedev02"
  resource_group_name = "rg-storage-baseline-test"
  location            = "eastus2"
}

run "consumer_can_opt_in_to_account_keys" {
  command = plan

  variables {
    shared_access_key_enabled = true
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == true
    error_message = "A consumer with a legitimate need could not re-enable shared access keys."
  }

  # The opt-out is scoped. Turning keys back on must not silently relax
  # anything else.
  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true && azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Opting in to account keys weakened an unrelated control."
  }
}

run "empty_lifecycle_rules_creates_no_policy" {
  command = plan

  variables {
    lifecycle_rules = []
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 0
    error_message = "An empty lifecycle_rules list still produced a management policy. Azure rejects a policy with zero rules."
  }
}

run "containers_are_created_and_forced_private" {
  command = plan

  variables {
    containers = {
      "artifacts" = {}
      "logs"      = { metadata = { retention = "90d" } }
    }
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected two containers to be planned."
  }

  assert {
    condition     = alltrue([for c in azurerm_storage_container.this : c.container_access_type == "private"])
    error_message = "A container was created with non-private access, contradicting allow_nested_items_to_be_public = false."
  }

  assert {
    condition     = azurerm_storage_container.this["logs"].metadata["retention"] == "90d"
    error_message = "Container metadata was not applied."
  }
}

run "ip_allowlist_is_applied" {
  command = plan

  variables {
    allowed_ip_ranges = ["203.0.113.10", "198.51.100.0/24"]
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].ip_rules) == 2
    error_message = "IP allowlist was not applied to the network rules."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Adding an allowlist must not change the default action away from Deny."
  }
}

# The network_rules block is always emitted (see the comment on it in main.tf:
# a dynamic block hid the control from static analysers and made it unknown at
# plan time). A consumer can still open the account up, and that must be
# visible in the plan rather than implied by an absent block.
run "network_rules_always_emitted_and_reflect_the_override" {
  command = plan

  variables {
    network_default_action = "Allow"
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules) == 1
    error_message = "The network_rules block must always be emitted so the account's network posture is explicit in the plan and visible to static analysis."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Allow"
    error_message = "network_default_action override was not applied."
  }

  assert {
    condition     = output.security_posture.network_default_action == "Allow"
    error_message = "security_posture must report the network action actually configured, not the module default."
  }
}

run "durability_can_be_raised_for_production" {
  command = plan

  variables {
    account_replication_type = "GZRS"
    tags = {
      portfolio   = "azure-devops-portfolio"
      project     = "storage-baseline"
      environment = "dev"
    }
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "GZRS"
    error_message = "Replication type could not be raised."
  }

  assert {
    condition     = azurerm_storage_account.this.tags["project"] == "storage-baseline"
    error_message = "Portfolio tags were not applied."
  }
}
