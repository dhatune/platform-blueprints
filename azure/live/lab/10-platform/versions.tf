terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }

  # Filled in with the outputs of live/00-bootstrap, passed on the command line:
  #   terraform init -backend-config=backend.hcl
  # backend.hcl is git ignored because it names the subscription's storage.
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # The object repository disables shared keys, and after creating a storage
  # account the provider polls its blob data plane to confirm it is ready --
  # using key authentication unless told otherwise. Without this the apply
  # fails with KeyBasedAuthenticationNotPermitted on an account that was in
  # fact created correctly.
  storage_use_azuread = true

  features {}
}
