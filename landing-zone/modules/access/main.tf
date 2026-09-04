# Access assignment for the hierarchy.
#
# Two rules shape everything here.
#
# First: bindings are made to groups, never to individuals. This is not
# tidiness. Access has to end when a person leaves, and that has to happen in
# one place — the directory — rather than by searching every folder and project
# in the organisation for their address. A binding to a person is a promise
# that somebody will remember to remove it, and that promise is kept for about
# as long as the person is remembered.
#
# Second: a role is granted at the level it is needed and no higher. Granting
# at the organisation to make one project work is the most common way least
# privilege dies, and it dies quietly, because the thing that was broken now
# works.

locals {
  # Flatten the per-folder role map into individual bindings so that a group
  # gaining a role in one folder cannot silently gain it everywhere.
  folder_bindings = flatten([
    for folder_key, grants in var.folder_access : [
      for grant in grants : {
        key       = "${folder_key}/${grant.group}/${grant.role}"
        folder_id = var.folder_ids[folder_key]
        role      = grant.role
        group     = grant.group
      }
    ]
  ])
}

resource "google_folder_iam_member" "access" {
  for_each = { for b in local.folder_bindings : b.key => b }

  folder = each.value.folder_id
  role   = each.value.role
  member = "group:${each.value.group}"
}

# The identity that applies infrastructure.
#
# It is deliberately not granted the ability to change who can apply
# infrastructure. Without that separation the approval gate in front of it is
# decorative: anything that can edit its own permissions can remove the gate,
# and an attacker who reaches it inherits that.
#
# This is the module's sharpest constraint and the one most likely to be
# removed during an incident, so the reason is stated where it is edited.
resource "google_folder_iam_member" "applier" {
  for_each = toset(var.applier_roles)

  folder = var.folder_ids[var.applier_folder]
  role   = each.value
  member = "serviceAccount:${var.applier_service_account}"
}

# Break-glass access exists because the alternative is worse: an organisation
# with no path to recovery invents one under pressure, and the improvised
# version is never removed.
#
# It is a group so that it holds no standing member. Adding someone is a
# deliberate act, visible in the directory's audit log, and the alert on that
# log is the actual control. The role binding here is only the mechanism.
resource "google_organization_iam_member" "break_glass" {
  count = var.break_glass_group == null ? 0 : 1

  org_id = var.organization_id
  role   = "roles/owner"
  member = "group:${var.break_glass_group}"
}
