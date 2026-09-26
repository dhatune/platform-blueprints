mock_provider "azurerm" {}

variables {
  name_prefix         = "opsalzlabeus201"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  location            = "eastus2"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  tags                = { environment = "lab" }
}

run "the_vault_is_closed_to_the_public_network" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "the vault must be reachable only through its private endpoint"
  }

  assert {
    condition     = one(azurerm_key_vault.this.network_acls).default_action == "Deny"
    error_message = "the network rules must deny by default, not allow"
  }
}

run "the_vault_cannot_be_wiped" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "purge protection is what stops an attacker, or a mistake, from destroying keys permanently"
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days >= 7
    error_message = "soft delete retention must give a real window to recover"
  }
}

run "authorisation_is_by_role_not_by_access_policy" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "role based authorisation keeps permissions in one system instead of two"
  }
}

run "the_name_fits_the_azure_limit" {
  command = plan

  assert {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", azurerm_key_vault.this.name))
    error_message = "key vault names are 3 to 24 characters, alphanumeric and dashes only"
  }
}

run "a_long_prefix_is_truncated_to_the_azure_limit" {
  command = plan

  # The run above proves nothing on its own: the default fixture yields an
  # 18 character name, already inside the limit, so removing the truncation
  # entirely would leave it green. This run supplies the longest prefix the
  # naming module can produce, where the truncation has to do real work.
  variables {
    name_prefix = "opsalzlabeus201abcdefghi"
  }

  assert {
    condition     = length(azurerm_key_vault.this.name) == 24
    error_message = "a name longer than the Azure limit must be truncated to exactly 24 characters"
  }

  assert {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", azurerm_key_vault.this.name))
    error_message = "the truncated name must still satisfy the Azure format"
  }
}

run "nothing_bypasses_the_deny_by_default" {
  command = plan

  # Without this the module can claim to be closed while quietly letting a
  # whole class of first-party services around the deny, and no test notices.
  assert {
    condition     = one(azurerm_key_vault.this.network_acls).bypass == "None"
    error_message = "the default posture must let nothing around the deny; AzureServices is an explicit opt-in"
  }
}

run "an_unknown_bypass_value_is_refused" {
  command = plan

  variables {
    network_bypass = "Everything"
  }

  expect_failures = [var.network_bypass]
}

run "a_retention_below_the_azure_floor_is_refused" {
  command = plan

  variables {
    soft_delete_retention_days = 3
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "the_vault_is_closed_to_the_public_network_by_default" {
  command = plan

  # The default must stay closed. An exception is something a caller asks for
  # in writing, never something the module grants quietly.
  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "the vault must be closed unless the caller explicitly opens it"
  }
}

run "an_exception_narrows_to_named_addresses_and_never_opens_the_default" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["203.0.113.10/32"]
  }

  # Opening the network plane must not open the vault. default_action stays
  # Deny, so only the named addresses are admitted; everything else is refused
  # exactly as before.
  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "an ip exception must never relax the default action"
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].ip_rules == toset(["203.0.113.10/32"])
    error_message = "the exception must admit exactly the addresses it was given"
  }
}

run "opening_the_network_without_naming_an_address_is_refused" {
  command = plan

  # An open vault with no allowlist is reachable by the whole internet with
  # only RBAC in front of it. That is the state this variable exists to make
  # impossible to reach by accident.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = []
  }

  expect_failures = [var.allowed_ip_rules]
}

run "a_bare_address_is_accepted_as_an_exception" {
  command = plan

  # A bare address, with no prefix at all, is the narrowest possible
  # exception -- one machine -- and must be admitted without a slash.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["203.0.113.10"]
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "a bare address exception must never relax the default action"
  }
}

run "a_slash_24_exception_is_accepted" {
  command = plan

  # /24 is the widest range this module treats as an operator exception --
  # one small office, not a swath of the internet.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["203.0.113.0/24"]
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].ip_rules == toset(["203.0.113.0/24"])
    error_message = "a /24 exception must admit exactly the range it was given"
  }
}

run "the_whole_internet_named_as_one_address_is_refused" {
  command = plan

  # 0.0.0.0/0 satisfies "name at least one address" while naming every
  # address. One invalid entry per run: expect_failures trips on the first
  # entry that fails, so mixing a valid entry in here would not prove this
  # one is the reason.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_ip_rules]
}

run "a_malformed_address_is_refused_by_the_modules_own_validation" {
  command = plan

  # Before the format validation existed, this string was refused only
  # because azurerm's own schema validator rejects it on ip_rules -- never
  # because this module checked it. expect_failures against var.allowed_ip_rules
  # (not the resource) proves the diagnostic comes from this module's own
  # validation block, not from a downstream provider check: a provider-level
  # rejection would attach to the resource attribute, not to the variable.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["not-an-ip-address"]
  }

  expect_failures = [var.allowed_ip_rules]
}

run "an_empty_string_entry_is_refused_by_the_modules_own_validation" {
  command = plan

  # Same defect, narrower shape: "" has no trailing "/N", so the old
  # width-only regex treated it as an unconstrained bare address and let it
  # through to azurerm's validator. It must be refused here, by this module.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = [""]
  }

  expect_failures = [var.allowed_ip_rules]
}

run "an_ipv6_literal_is_refused_by_the_modules_own_validation" {
  command = plan

  # Confirms the fix covers the third case named alongside
  # malformed and empty strings: an address family this module never
  # intended to admit, refused by its own IPv4-only pattern.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["2001:db8::1"]
  }

  expect_failures = [var.allowed_ip_rules]
}

run "a_prefix_wider_than_32_is_refused_by_the_modules_own_validation" {
  command = plan

  # /33 is not a valid IPv4 prefix at all -- calling
  # cidrhost(rule, 0) on it unconditionally, which is itself a raw
  # "invalid CIDR address" function-call error, not a validation failure this
  # module owns. expect_failures only matches a clean failure attributed to
  # var.allowed_ip_rules; a bare function-call error surfaces as an
  # unexpected run error instead and this run would not pass. That is what
  # proves the guard: this run only goes green once the prefix-<=32 check
  # runs before cidrhost ever sees the value.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["203.0.113.0/33"]
  }

  expect_failures = [var.allowed_ip_rules]
}

run "a_cidr_with_host_bits_set_is_refused" {
  command = plan

  # 203.0.113.5/24 passes both older checks: it is a well formed IPv4/prefix
  # pair, and /24 is inside the width limit. It still names one host wearing
  # a /24 label, not the range 203.0.113.0/24 an operator would mean by that
  # prefix -- azurerm's own ip_rules validator does not catch this either.
  # This is the same shape as the unmasked-CIDR defect modules/aks and
  # live/lab/10-platform's overlap guards already correct for with
  # cidrhost(cidr, 0); this run proves this module's own copy of that guard
  # actually reddens on the input it exists for.
  variables {
    public_network_access_enabled = true
    allowed_ip_rules              = ["203.0.113.5/24"]
  }

  expect_failures = [var.allowed_ip_rules]
}
