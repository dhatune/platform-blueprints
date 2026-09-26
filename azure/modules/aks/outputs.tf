output "cluster_id" {
  description = "Cluster identifier."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "Issuer the federated credential trusts. Consumed by the identity module."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Identity the nodes pull images with."

  # kubelet_identity is a computed BLOCK this module never declares. Azure's
  # provider returns it unknown while planning and populated after the apply, so
  # this index always resolves and the fallback never reaches a caller. A mocked
  # provider returns a known empty list, which fails the plan outright; the
  # fallback exists so the module can be planned under one. The nil GUID marks
  # "no principal" unmistakably should it ever surface here.
  # Upstream: hashicorp/terraform-provider-azurerm#25691.
  value = try(azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id, "00000000-0000-0000-0000-000000000000")
}

output "control_plane_identity_id" {
  description = "Resource identifier of the control plane's user-assigned identity."
  value       = azurerm_user_assigned_identity.control_plane.id
}

output "control_plane_principal_id" {
  description = <<-EOT
    Identity the control plane manages network resources with. Read from the
    user-assigned identity this module creates, not from the cluster's own
    identity block: with type UserAssigned, identity[0].principal_id on the
    cluster itself is not the value a caller wants here.
  EOT
  value       = azurerm_user_assigned_identity.control_plane.principal_id
}

output "private_fqdn" {
  description = "Private name of the API server. There is no public one."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

# Echo-backs of the wiring a stack test cannot otherwise reach. A caller's
# test can address this module's own outputs but not its resources, so
# without these there is no way to assert -- from the composing stack -- that
# the subnet and the two role assignments received what the stack intended
# rather than some other, equally plausible-looking value.

output "node_pool_subnet_id" {
  description = "Echoes var.subnet_id, so a caller can assert the node pool attaches to the subnet the stack actually intended."
  value       = var.subnet_id
}

output "network_subnet_role_definition_name" {
  description = "Role name of the control plane's role assignment on the cluster subnet."
  value       = azurerm_role_assignment.network_subnet.role_definition_name
}

output "network_subnet_role_scope" {
  description = "Scope of the control plane's role assignment on the cluster subnet, so a caller can assert the role and the scope separately -- a role granted at the wrong scope is the defect that actually happens."
  value       = azurerm_role_assignment.network_subnet.scope
}

output "network_route_table_role_definition_name" {
  description = "Role name of the control plane's role assignment on the spoke's route table."
  value       = azurerm_role_assignment.network_route_table.role_definition_name
}

output "network_route_table_role_scope" {
  description = "Scope of the control plane's role assignment on the spoke's route table, asserted separately from the role name for the same reason as above."
  value       = azurerm_role_assignment.network_route_table.scope
}

output "acr_pull_role_definition_name" {
  description = "Role name of the kubelet identity's registry role assignment."
  value       = azurerm_role_assignment.acr_pull.role_definition_name
}

output "acr_pull_role_scope" {
  description = "Scope of the kubelet identity's registry role assignment, asserted separately from the role name for the same reason as above."
  value       = azurerm_role_assignment.acr_pull.scope
}
