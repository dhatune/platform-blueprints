# Naming and tagging contract for the whole landing zone.
#
# Every other module receives the strings this module produces and decorates
# them with its own resource type prefix -- "rg-", "vnet-", "nsg-", "kv-" and
# so on. What is centralised here is the shared part of every name, so renaming
# a scope is a change in one place; the type prefix stays with the module that
# knows what it is creating.

locals {
  base = lower(join("-", [
    var.prefix,
    var.workload,
    var.environment,
    var.location_short,
    var.instance,
  ]))

  # Storage account names admit only lowercase alphanumerics, 3 to 24 characters.
  storage_base = substr(replace(local.base, "/[^a-z0-9]/", ""), 0, 24)

  required_tags = {
    environment = var.environment
    workload    = var.workload
    managed_by  = "terraform"
  }
}
