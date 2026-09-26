variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "purpose" {
  description = "What this identity is for, in one lowercase word. Becomes part of the name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the identity is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "oidc_issuer_url" {
  description = <<-EOT
    Issuer URL published by the Kubernetes cluster. Empty until the cluster
    exists, which is why the federated credential is conditional: the identity
    can be planned and created before the cluster it will serve.
  EOT
  type        = string
  default     = ""
}

variable "service_account_namespace" {
  description = "Kubernetes namespace of the service account allowed to assume this identity."
  type        = string
  default     = ""
}

variable "service_account_name" {
  description = "Kubernetes service account allowed to assume this identity."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}
