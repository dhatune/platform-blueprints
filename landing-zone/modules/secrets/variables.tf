variable "project_id" {
  description = "Project holding the secrets."
  type        = string
}

variable "secrets" {
  description = <<-EOT
    Secret containers to create. Values are never set here: a value in the
    configuration is a value in the state file.

    accessors are granted read on that secret alone. regions null replicates
    automatically; a list pins replication, which is what data residency
    requirements need. rotation_days null records no rotation date, which is
    a decision rather than a default.
  EOT
  type = map(object({
    accessors = optional(list(string), [])
    labels    = optional(map(string), {})
    regions   = optional(list(string))

    # A schedule needs somewhere to publish to, because the schedule is a
    # notification rather than an action. Naming the topic is what makes that
    # obvious at the point of use.
    rotation = optional(object({
      days  = number
      topic = string
    }))
  }))
  default = {}

  validation {
    # Catches the mistake this module exists to prevent, in the one place it
    # can be caught automatically: somebody adding a value-shaped field.
    condition = alltrue([
      for k, v in var.secrets : !can(regex("(?i)(password|token|key)$", k)) || length(v.accessors) > 0
    ])
    error_message = "A secret that looks like a credential with no accessors is probably unfinished; name who reads it."
  }
}
