terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }

  # No backend block on purpose. This stack creates the storage every other
  # stack keeps its state in, so its own state cannot live there. It stays
  # local, and it is cheap to rebuild: every resource here is idempotent.
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # The state account disables shared keys, and after creating a storage
  # account the provider polls its blob data plane to confirm it is ready --
  # using key authentication unless told otherwise. Without this the apply
  # fails with KeyBasedAuthenticationNotPermitted on an account that was in
  # fact created correctly. Consistent with every backend block in this
  # repository, which already authenticates with use_azuread_auth = true.
  storage_use_azuread = true

  features {}
}
