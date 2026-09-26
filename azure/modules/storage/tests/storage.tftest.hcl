mock_provider "azurerm" {}

variables {
  storage_base        = "opsalzlabeus201"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  location            = "eastus2"
  replication_type    = "LRS"
  tags                = { environment = "lab" }
}

run "the_account_is_closed_and_encrypted_in_transit" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "objects must be reachable only through the private endpoint"
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "plain HTTP to an object store is never acceptable"
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "TLS below 1.2 must be refused"
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "individual containers must not be able to opt back into public access"
  }
}

run "deletion_is_recoverable" {
  command = plan

  assert {
    condition     = one(azurerm_storage_account.this.blob_properties).versioning_enabled == true
    error_message = "versioning is what makes a bad overwrite recoverable"
  }

  assert {
    condition     = one(one(azurerm_storage_account.this.blob_properties).delete_retention_policy).days == 14
    error_message = "soft delete must retain for the configured window"
  }
}

run "a_deleted_container_is_recoverable_too" {
  command = plan

  # Deleting a container takes every blob inside it. Asserting only the blob
  # level policy leaves the larger accident unguarded.
  assert {
    condition     = one(one(azurerm_storage_account.this.blob_properties).container_delete_retention_policy).days == 14
    error_message = "a deleted container must be recoverable on the same window as a deleted blob"
  }
}

run "the_account_kind_supports_the_protections_this_module_claims" {
  command = plan

  # The legacy Storage kind supports neither versioning nor lifecycle
  # management, so a regression to it would quietly void two of the guarantees
  # asserted above while every other run stayed green.
  assert {
    condition     = azurerm_storage_account.this.account_kind == "StorageV2"
    error_message = "the account kind must be one that supports versioning and lifecycle management"
  }
}

run "the_account_name_obeys_the_azure_format" {
  command = plan

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", azurerm_storage_account.this.name))
    error_message = "storage account names are 3 to 24 lowercase alphanumeric characters"
  }
}

run "a_long_base_is_truncated_to_the_azure_limit" {
  command = plan

  # The format assertion above proves nothing on its own: the default fixture
  # yields a 17 character name, already inside the limit, so removing the
  # truncation entirely would leave it green. This supplies the longest base
  # the naming module can produce, where the truncation has to do real work.
  variables {
    storage_base = "opsalzlabeus201abcdefghi"
  }

  assert {
    condition     = length(azurerm_storage_account.this.name) == 24
    error_message = "a name longer than the Azure limit must be truncated to exactly 24 characters"
  }
}

run "shared_keys_are_disabled_so_access_is_by_identity" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "a shared key is a static credential; access to the repository is by identity only"
  }
}

run "the_lifecycle_moves_and_expires_what_it_claims" {
  command = plan

  # The lifecycle is what keeps cost proportional to the age of the content.
  # Declaring it without asserting it means a silently broken rule keeps
  # everything in the hot tier and nobody finds out until the invoice.
  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).actions).base_blob[0].tier_to_cool_after_days_since_modification_greater_than == 90
    error_message = "the cool transition must use the configured age"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).actions).base_blob[0].tier_to_archive_after_days_since_modification_greater_than == 365
    error_message = "the archive transition is half of what this rule claims to do and must be pinned too"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).actions).version[0].delete_after_days_since_creation == 14
    error_message = "superseded versions must expire on the soft delete window, or they accumulate forever"
  }

  assert {
    condition     = one(azurerm_storage_management_policy.this.rule).enabled == true
    error_message = "a disabled rule applies nothing; the entire policy becomes a no-op in silence"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).filters).prefix_match == toset(["objects/"])
    error_message = "the rule must be scoped to the repository container"
  }
}

run "the_repository_container_refuses_anonymous_read" {
  command = plan

  assert {
    condition     = azurerm_storage_container.this.container_access_type == "private"
    error_message = "the container must never permit anonymous read, whatever the account level settings say"
  }
}

run "the_lifecycle_scope_follows_the_container_name" {
  command = plan

  # Overriding the container proves the rule scope is derived rather than
  # fixed, and pins the blob type the rule applies to.
  variables {
    container_name = "records"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).filters).prefix_match == toset(["records/"])
    error_message = "the rule scope must follow the container name, not a fixed string"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).filters).blob_types == toset(["blockBlob"])
    error_message = "the rule must apply to ordinary blobs, not to a type nothing writes"
  }
}

run "archive_tiering_is_dropped_on_a_zone_redundant_profile" {
  command = plan

  # Azure refuses the archive tier outright on ZRS, GZRS and RA-GZRS. Without
  # this the lifecycle rule plans clean against every profile and then fails
  # at apply the moment a caller picks the one redundancy tier it does not
  # support.
  variables {
    replication_type = "ZRS"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).actions).base_blob[0].tier_to_archive_after_days_since_modification_greater_than == null
    error_message = "the archive transition must be omitted on a profile Azure refuses to apply it to, not merely documented as unsupported"
  }

  assert {
    condition     = one(one(azurerm_storage_management_policy.this.rule).actions).base_blob[0].tier_to_cool_after_days_since_modification_greater_than == 90
    error_message = "dropping the archive transition must not also drop the cool transition, which every profile supports"
  }
}

run "the_replication_profile_is_the_only_thing_the_caller_changes" {
  command = plan

  variables {
    replication_type = "GZRS"
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "GZRS"
    error_message = "a production composition must be able to ask for zone and geo redundancy"
  }

  # The run is named for a claim, so it has to hold the claim. Asserting one
  # protection proves nothing about the others moving with the profile.
  assert {
    condition = (
      one(azurerm_storage_account.this.blob_properties).versioning_enabled == true
      && one(one(azurerm_storage_account.this.blob_properties).delete_retention_policy).days == 14
      && one(one(azurerm_storage_account.this.blob_properties).container_delete_retention_policy).days == 14
      && azurerm_storage_account.this.public_network_access_enabled == false
      && azurerm_storage_account.this.shared_access_key_enabled == false
      && one(azurerm_storage_management_policy.this.rule).enabled == true
    )
    error_message = "no protection may change with the redundancy profile; only redundancy changes"
  }
}
