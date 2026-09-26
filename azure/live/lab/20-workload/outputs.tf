output "cluster_name" {
  description = "Cluster name, for az aks get-credentials."
  value       = module.aks.cluster_name
}

output "cluster_private_fqdn" {
  description = "Private name of the API server."
  value       = module.aks.private_fqdn
}

output "oidc_issuer_url" {
  description = "Issuer a federated credential must trust."
  value       = module.aks.oidc_issuer_url
}

output "registry_login_server" {
  description = "Host to push images to. Resolves privately from inside the network only."
  value       = module.acr.login_server
}

output "firewall_public_ip" {
  description = "The single address everything leaving the landing zone is seen as."
  value       = module.firewall.public_ip
}

output "firewall_private_ip" {
  description = "Next hop of the spoke's default route. Must equal the address the route already names."
  value       = module.firewall.private_ip
}

output "federated_credential_subject" {
  description = "Kubernetes subject the workload identity's federated credential trusts."
  value       = azurerm_federated_identity_credential.workload.subject
}

output "workload_probe_secret_name" {
  description = <<-EOT
    Name of the vault secret check 4 reads by workload identity. Published so
    the check reads the name from the stack that writes it: a SecretNotFound
    would be indistinguishable, to that check's own pass/fail test, from the
    identity being denied. A check must not depend on a component it is not
    testing.
  EOT
  value       = azurerm_key_vault_secret.probe.name
}

output "ingress_internal_address" {
  description = <<-EOT
    Private address the firewall's translation rule forwards to, and the
    address the ingress controller's load balancer must hold. Published so
    scripts/ingress/install-nginx.sh can compare it against its own copy and
    refuse to install when the two disagree, rather than producing a load
    balancer at one address and a firewall rule pointing at another -- which
    fails as a connection that times out with nothing in any log.
  EOT
  value       = var.ingress_internal_address
}
