# Object repository.
#
# Redundancy is the only setting var.replication_type changes. Versioning, soft
# delete and the lifecycle stay fixed across every value of it, because they
# are configuration rather than cost, and a protection that only some callers
# switch on is a protection nobody has exercised by the time it is needed.

resource "azurerm_storage_account" "this" {
  name                = substr("st${var.storage_base}", 0, 24)
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = var.replication_type

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

locals {
  # The archive tier is not offered on a zone-redundant profile -- ZRS, GZRS
  # and RA-GZRS all refuse it. Declaring the transition unconditionally would
  # plan clean against LRS, GRS and RAGRS and then fail at apply the moment a
  # caller asked for zone redundancy, which is exactly the profile most
  # likely to want the lifecycle rule working correctly. The transition is
  # left out of the actions block entirely for those three profiles rather
  # than merely documented as unsupported.
  archive_tier_supported = contains(["LRS", "GRS", "RAGRS"], var.replication_type)
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tier-by-age"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${var.container_name}/"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.cool_after_days
        tier_to_archive_after_days_since_modification_greater_than = local.archive_tier_supported ? var.archive_after_days : null
      }

      version {
        delete_after_days_since_creation = var.soft_delete_days
      }
    }
  }
}
