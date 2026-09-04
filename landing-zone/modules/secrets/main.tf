# Secrets as a platform concern.
#
# This module creates the containers and decides who may read them. It never
# creates a version, and that omission is the entire point.
#
# A value written here is written into the state file, in clear. The state then
# holds every credential the estate has, is copied to whoever runs a plan, and
# is backed up. The tool that was supposed to keep the secret out of the
# repository has put it somewhere with a worse access policy and no audit
# trail.
#
# The same mistake wears other clothes. A password passed to a deployment tool
# as a value is stored in that tool's release history inside the cluster, in
# clear, readable by anyone who can read secrets in the namespace, surviving
# every upgrade and the departure of whoever set it. Nobody chose that location
# and nobody reviewed its access policy.
#
# So versions are created out of band, by a person, from a generator, piped in
# rather than typed, and this module holds only the container and the grants.

resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  secret_id = each.key
  project   = var.project_id

  labels = each.value.labels

  replication {
    dynamic "auto" {
      for_each = each.value.regions == null ? [1] : []
      content {}
    }

    dynamic "user_managed" {
      for_each = each.value.regions == null ? [] : [1]
      content {
        dynamic "replicas" {
          for_each = each.value.regions
          content {
            location = replicas.value
          }
        }
      }
    }
  }

  # A rotation schedule here does not rotate anything. It publishes a message
  # when the date arrives, and something else has to act on it.
  #
  # The platform makes that explicit by refusing a schedule without somewhere
  # to publish to, which is the API saying what the feature is: a reminder with
  # a delivery address, not a mechanism. Setting it without building the
  # listener produces a secret that looks managed and is not.
  #
  # It is still worth setting, because a secret with no date is one nobody will
  # revisit, and the message at least lands somewhere a person can be paged
  # from.
  dynamic "rotation" {
    for_each = each.value.rotation == null ? [] : [1]
    content {
      next_rotation_time = timeadd(timestamp(), "${each.value.rotation.days * 24}h")
      rotation_period    = "${each.value.rotation.days * 24 * 3600}s"
    }
  }

  dynamic "topics" {
    for_each = each.value.rotation == null ? [] : [1]
    content {
      name = each.value.rotation.topic
    }
  }

  lifecycle {
    # The rotation time moves on every plan otherwise, producing a diff that
    # teaches people to ignore diffs.
    ignore_changes = [rotation[0].next_rotation_time]
  }
}

# Access is granted per secret. A project-level grant gives a reader every
# secret the project will ever hold, including the ones added after the grant
# was reviewed, which is how a service ends up able to read credentials for
# systems it has no relationship with.
resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = {
    for pair in flatten([
      for secret_id, config in var.secrets : [
        for index, member in config.accessors : {
          key    = "${secret_id}-${index}"
          secret = secret_id
          member = member
        }
      ]
    ]) : pair.key => pair
  }

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
