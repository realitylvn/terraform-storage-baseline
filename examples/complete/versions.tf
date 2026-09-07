terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # No backend block. State is local for this example, deliberately: a remote
  # state backend needs a storage account, which is the thing this module
  # creates. Bootstrapping that chicken-and-egg is a separate concern and is
  # documented in the README rather than half-built here.
}

provider "azurerm" {
  features {
    resource_group {
      # Fail loudly rather than silently orphaning resources this example did
      # not create.
      prevent_deletion_if_contains_resources = true
    }
  }

  # Supplied via ARM_SUBSCRIPTION_ID or terraform.tfvars — never hardcoded.
  subscription_id = var.subscription_id

  # REQUIRED when consuming secure-storage with its default
  # shared_access_key_enabled = false. Not optional, and not a style choice.
  #
  # After creating a storage account, the provider polls the Blob Service for
  # data-plane readiness. That poll authenticates with an account key by
  # default, so on an account that just disabled key auth it returns:
  #
  #   403 KeyBasedAuthenticationNotPermitted
  #   Key based authentication is not permitted on this storage account.
  #
  # The account itself is created correctly and lands in state; it is the
  # readiness check that fails, which makes the error look far worse than it
  # is. Setting this switches the provider's data-plane calls to Entra ID.
  storage_use_azuread = true
}
