output "location" {
  description = "Region the platform was created in."
  value       = var.location
}

output "spoke_resource_group_name" {
  description = "Resource group the workload stack creates its resources in."
  value       = module.spoke.resource_group_name
}

output "subnet_ids" {
  description = "Spoke subnet identifiers keyed by zone name."
  value       = module.spoke.subnet_ids
}

output "private_dns_zone_ids" {
  description = "Private DNS zone identifiers keyed by zone name, consumed by private endpoints."
  value       = module.private_dns.zone_ids
}

output "key_vault_id" {
  description = "Vault the workload reads secrets from."
  value       = module.keyvault.key_vault_id
}

output "storage_account_id" {
  description = "Object repository the workload writes to."
  value       = module.storage.storage_account_id
}

output "workload_identity_id" {
  description = "Managed identity the workload assumes."
  value       = module.workload_identity.identity_id
}

output "workload_identity_client_id" {
  description = "Client identifier annotated on the Kubernetes service account."
  value       = module.workload_identity.client_id
}

output "workload_identity_principal_id" {
  description = <<-EOT
    Principal the workload identity presents. The vault authorises by role and
    the repository refuses shared keys, so every grant the ephemeral stack makes
    names this value; without it that stack has to look the identity up again
    and can look up the wrong one.
  EOT
  value       = module.workload_identity.principal_id
}

output "spoke_route_table_name" {
  description = "Route table carrying the spoke's default route through the firewall."
  value       = module.spoke.route_table_name
}

output "spoke_route_table_id" {
  description = "Identifier of the spoke's route table."
  value       = module.spoke.route_table_id
}


output "spoke_default_route_next_hop" {
  description = <<-EOT
    Address the spoke's default route already points at. The workload layer
    reads it rather than restating it, so the firewall it creates and the route
    that was written before that firewall existed cannot drift apart.
  EOT
  value       = var.firewall_private_ip
}

output "hub_resource_group_name" {
  description = "Resource group the firewall is created in."
  value       = module.hub.resource_group_name
}

output "firewall_subnet_id" {
  description = "Subnet the firewall's data plane attaches to."
  value       = module.hub.firewall_subnet_id
}

output "firewall_management_subnet_id" {
  description = "Subnet the firewall's management plane attaches to."
  value       = module.hub.firewall_management_subnet_id
}

output "key_vault_private_endpoint_ip" {
  description = "Address the vault answers on inside the network."
  value       = module.keyvault_endpoint.private_ip
}

output "storage_private_endpoint_ip" {
  description = "Address the object repository answers on inside the network."
  value       = module.storage_endpoint.private_ip
}

output "log_analytics_workspace_id" {
  description = "Workspace the ephemeral layer's diagnostic settings send to."
  value       = module.observability.workspace_id
}

output "deny_public_nic_assignment_name" {
  description = "The policy assignment check 7 expects Azure to cite when it refuses a public address."
  value       = module.policy.deny_public_nic_assignment_name
}

output "spoke_address_space" {
  description = <<-EOT
    Address space of the spoke. The ephemeral layer's firewall reads this to
    scope its own egress rules to the spoke rather than to every address on
    the internet.
  EOT
  value       = var.spoke_address_space
}

output "application_security_group_id" {
  description = <<-EOT
    Group the vault and registry private endpoints join. The ephemeral
    layer's registry endpoint joins the same group, and its firewall-adjacent
    allow rule targets it as a destination instead of the whole endpoints
    subnet.
  EOT
  value       = azurerm_application_security_group.cluster_reachable.id
}

output "pod_cidr" {
  description = "Pod address space the cluster must use; the workload layer reads it from here."
  value       = var.pod_cidr
}
