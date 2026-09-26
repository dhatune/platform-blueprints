terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }

  # Filled in with the outputs of live/00-bootstrap, passed on the command line:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # Same reason as the platform stack: the object repository disables shared
  # keys and the provider polls blob data planes with key auth unless told
  # otherwise.
  storage_use_azuread = true

  features {}
}
