variable "name" {
  description = "Cluster name."
  type        = string
}

variable "project_id" {
  description = "Project the cluster runs in."
  type        = string
}

variable "project_number" {
  description = "Numeric ID of that project, needed to name its service agent."
  type        = string
}

variable "host_project_id" {
  description = "Project owning the shared network."
  type        = string
}

variable "network_id" {
  description = "Network the nodes attach to."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the nodes attach to."
  type        = string
}

variable "location" {
  description = "Zone or region. A zone is one control plane and is cheaper; a region is three."
  type        = string
}

variable "pod_range_name" {
  description = "Secondary range on the subnet that pods draw from."
  type        = string
  default     = "pods"
}

variable "service_range_name" {
  description = "Secondary range on the subnet that services draw from."
  type        = string
  default     = "services"
}

variable "machine_type" {
  description = "Node machine type."
  type        = string
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  description = "Node boot disk."
  type        = number
  default     = 50
}

variable "node_count" {
  description = "Nodes in the default pool."
  type        = number
  default     = 2
}

variable "spot" {
  description = "Interruptible capacity. See ADR 8 before setting this for anything stateful."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster. False only for something meant to be torn down."
  type        = bool
  default     = true
}

variable "monitoring_components" {
  description = <<-EOT
    Metric collectors to enable. The platform's default is every one of them,
    each billable, so this is stated rather than inherited.
  EOT
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}
