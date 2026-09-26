output "base" {
  description = "Dash separated base name for resources that accept dashes."
  value       = local.base
}

output "storage_base" {
  description = "Alphanumeric base name for resources that reject dashes, such as storage accounts."
  value       = local.storage_base
}

output "tags" {
  description = "Tags applied to every resource. Required keys win over extra_tags."
  value       = merge(var.extra_tags, local.required_tags)
}
