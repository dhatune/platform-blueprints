variable "project_id" {
  description = "Project holding the registries. Usually the shared one, not a product's."
  type        = string
}

variable "region" {
  description = "Region for the repositories. Keep it where the clusters that pull are."
  type        = string
  default     = "us-east1"
}

variable "repositories" {
  description = <<-EOT
    Repositories holding images put there deliberately: built here, or copied
    from upstream at a reviewed digest. Point production at these.
  EOT
  type = map(object({
    description       = string
    keep_versions     = optional(number, 10)
    delete_after_days = optional(number, 90)
  }))
  default = {}
}

variable "remote_repositories" {
  description = <<-EOT
    Caching proxies. upstream is either "docker-hub" or the URL of another
    registry. Useful for development and for anything whose disappearance you
    could tolerate; not a substitute for holding a copy of what production runs.
  EOT
  type = map(object({
    description = string
    upstream    = string
  }))
  default = {}
}

variable "readers" {
  description = <<-EOT
    Members granted read on each repository, keyed by repository id. Node
    service accounts belong here. Nothing that runs workloads should be able to
    write to a registry it also pulls from.
  EOT
  type        = map(list(string))
  default     = {}
}
