# The point of this file: prove the module REFUSES insecure or invalid input
# rather than quietly accepting it. Every run here expects a failure.

mock_provider "azurerm" {}

variables {
  name                = "sttestbaselinedev01"
  resource_group_name = "rg-storage-baseline-test"
  location            = "eastus2"
}

run "rejects_tls_1_0" {
  command = plan

  variables {
    min_tls_version = "TLS1_0"
  }

  expect_failures = [var.min_tls_version]
}

run "rejects_tls_1_1" {
  command = plan

  variables {
    min_tls_version = "TLS1_1"
  }

  expect_failures = [var.min_tls_version]
}

# Refused for a provider reason, not a security one: azurerm 4.81 accepts only
# TLS1_0, TLS1_1 and TLS1_2 for this field. Catching it in variable validation
# turns an opaque provider error into a clear message. When the provider adds
# TLS1_3, this run block becomes an "accepts raising the floor" assertion.
run "rejects_tls_1_3_pending_provider_support" {
  command = plan

  variables {
    min_tls_version = "TLS1_3"
  }

  expect_failures = [var.min_tls_version]
}

run "rejects_storage_account_name_with_hyphens" {
  command = plan

  variables {
    name = "st-storage-baseline-dev"
  }

  expect_failures = [var.name]
}

run "rejects_storage_account_name_over_24_chars" {
  command = plan

  variables {
    name = "ststoragebaselinedevfartoolong"
  }

  expect_failures = [var.name]
}

run "rejects_legacy_account_kind" {
  command = plan

  variables {
    account_kind = "BlobStorage"
  }

  expect_failures = [var.account_kind]
}

run "rejects_out_of_range_soft_delete_retention" {
  command = plan

  variables {
    blob_soft_delete_retention_days = 400
  }

  expect_failures = [var.blob_soft_delete_retention_days]
}

run "rejects_invalid_container_name" {
  command = plan

  variables {
    containers = {
      "Not_A_Valid_Name" = {}
    }
  }

  expect_failures = [var.containers]
}

# A resource precondition, not a variable validation: the two inputs are each
# individually valid but contradict one another.
run "rejects_ip_allowlist_while_public_endpoint_is_off" {
  command = plan

  variables {
    public_network_access_enabled = false
    allowed_ip_ranges             = ["203.0.113.10"]
  }

  expect_failures = [azurerm_storage_account.this]
}
