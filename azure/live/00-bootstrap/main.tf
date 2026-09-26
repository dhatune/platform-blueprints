# Bootstrap: the storage every other stack keeps its state in.
#
# This deliberately does NOT use the storage module. That module closes the
# public network, which is right for an object repository sitting behind a
# private endpoint, and wrong for a state store that has to be reachable from
# a workstation before any network exists. The exception is declared here
# rather than weakened there.

module "naming" {
  source = "../../modules/naming"

  prefix         = var.prefix
  workload       = var.workload
  environment    = var.environment
  location_short = var.location_short
  instance       = "01"

  extra_tags = {
    purpose = "terraform-state"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${module.naming.base}-tfstate"
  location = var.location
  tags     = module.naming.tags
}

resource "azurerm_storage_account" "state" {
  # The discriminator LEADS the name. Both this account and the object
  # repository in modules/storage derive from the same base, and storage
  # account names are globally unique in Azure, so a collision surfaces as a
  # baffling conflict on a second apply.
  #
  # A trailing discriminator does not prevent that. Truncation eats it when
  # names are longest, and even truncating the base first only moves the
  # problem: "st" + base[0:20] + "tf" equals "st" + base[0:22] whenever the
  # base happens to carry "tf" at those two positions, which is reachable with
  # perfectly ordinary inputs. Leading it makes the two structurally
  # incomparable -- that name always begins "st", this one always begins
  # "tf" -- and no content of the shared base can change that.
  name                = substr("tfstate${module.naming.storage_base}", 0, 24)
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"

  # Shared keys stay disabled here too. Every backend block in this
  # repository already authenticates with use_azuread_auth = true, and this
  # stack's own provider carries storage_use_azuread = true for the same
  # reason live/lab's does -- so nothing ever needs the account key, and a
  # key nobody uses is a static credential kept alive for no purpose.
  # azurerm_role_assignment.deployer_state_data below is what actually grants
  # whoever runs Terraform access to this account's data plane.
  shared_access_key_enabled = false

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.state_retention_days
    }
  }

  tags = module.naming.tags
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Whoever runs Terraform is the one who reads and writes state, and every
# other stack reaches this account with Entra ID rather than an access key.
# Owner on the subscription does not include the data plane, so without this
# grant the first `terraform init` of the next stack fails with a 403 on an
# account the same person just created. Role assignments take a few minutes
# to propagate: wait before initialising the next stack.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "deployer_state_data" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
