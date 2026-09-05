variable "organization_id" {
  description = "Numeric organization id."
  type        = string
}

variable "folder_ids" {
  description = "Map of folder key to folder id, as produced by the folders module."
  type        = map(string)
}

variable "folder_access" {
  description = <<-EOT
    Role grants per folder, keyed by the same folder keys as folder_ids.
    Every member is a group address; individuals are refused by validation.
  EOT
  type = map(list(object({
    group = string
    role  = string
  })))
  default = {}

  validation {
    # Primitive roles are refused. They are convenient exactly because they are
    # broad, and a landing zone that admits them at folder level has no least
    # privilege regardless of what the rest of it says.
    condition = alltrue([
      for grants in values(var.folder_access) : alltrue([
        for g in grants : !contains(
          ["roles/owner", "roles/editor", "roles/viewer"], g.role
        )
      ])
    ])
    error_message = "Primitive roles (owner, editor, viewer) are not allowed. Use a predefined role that names what is actually needed."
  }
}

variable "applier_service_account" {
  description = "Email of the service account that runs infrastructure changes."
  type        = string
}

variable "applier_folder" {
  description = "Folder key the applier's roles are scoped to."
  type        = string
}

variable "applier_roles" {
  description = <<-EOT
    Roles the applier holds over its folder. Deliberately excludes anything
    that can change IAM policy, so it cannot widen its own access.
  EOT
  type        = list(string)

  validation {
    condition = alltrue([
      for r in var.applier_roles : !contains([
        "roles/owner",
        "roles/iam.securityAdmin",
        "roles/resourcemanager.folderAdmin",
        "roles/resourcemanager.organizationAdmin",
      ], r)
    ])
    error_message = "The applier must not hold a role that can change IAM policy, or the approval gate in front of it is decorative."
  }
}

variable "break_glass_group" {
  description = <<-EOT
    Group granted owner at the organization for emergency recovery. Expected to
    hold no standing member; adding one should raise an alert. Null disables it.
  EOT
  type        = string
  default     = null
}
