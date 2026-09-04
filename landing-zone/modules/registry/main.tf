# Where the cluster's images come from.
#
# A cluster that pulls straight from a public registry has taken on a
# dependency it does not control and mostly cannot see. Three things go wrong
# with it, in rising order of how badly.
#
# Anonymous pulls from public registries are rate limited, and the limit is per
# source address. A cluster that scales out, or a node pool that recycles, can
# exhaust it and then pods stop starting, during an incident, which is exactly
# when nodes recycle.
#
# A tag can be moved. This repository argues that elsewhere and pins by digest
# because of it. Pinning stops you running something you did not review; it
# does not stop the thing you did review from being deleted upstream.
#
# And the image can simply cease to exist. Upstream deletes it, the account
# goes away, the project is renamed. What ran yesterday cannot be rebuilt.
#
# Two mechanisms, and the difference between them is worth understanding rather
# than picking by which is less typing.

# A remote repository is a caching proxy: the cluster pulls from here, and on a
# miss this fetches from upstream and keeps a copy. Nothing to run, nothing to
# schedule, and it fixes rate limits and locality on its own.
#
# What it does not fix is survival on its own terms. It caches what was asked
# for; it is not a promise that a given digest is retained forever, and a tag
# still resolves upstream on a miss. Good for the common case, not a substitute
# for holding a copy of what production runs.
resource "google_artifact_registry_repository" "remote" {
  for_each = var.remote_repositories

  project       = var.project_id
  location      = var.region
  repository_id = each.key
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  description   = each.value.description

  remote_repository_config {
    description = "Cache of ${each.value.upstream}"

    dynamic "docker_repository" {
      for_each = each.value.upstream == "docker-hub" ? [1] : []
      content {
        public_repository = "DOCKER_HUB"
      }
    }

    dynamic "docker_repository" {
      for_each = each.value.upstream != "docker-hub" ? [1] : []
      content {
        custom_repository {
          uri = each.value.upstream
        }
      }
    }
  }
}

# A standard repository holds images that were put there deliberately: things
# built here, and copies of third-party images taken at a reviewed digest.
#
# This is the one to point production at. Copying an image into it is an
# explicit act with a date and an author, and the copy survives whatever
# happens upstream afterwards.
resource "google_artifact_registry_repository" "standard" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.region
  repository_id = each.key
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"
  description   = each.value.description

  # Old images accumulate quietly and are charged for just as quietly. Keeping
  # a fixed number of recent versions bounds that without anyone remembering to
  # prune. Deleting untagged images instead would be a mistake: a multi
  # architecture image is an index pointing at per-platform manifests that carry
  # no tags of their own, and removing them breaks the image for every platform.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = each.value.keep_versions
    }
  }

  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      older_than = "${each.value.delete_after_days * 86400}s"
    }
  }
}

# Nodes need to read, and nothing more. A cluster that can write to the registry
# it pulls from turns a compromised workload into a supply chain problem for
# everything else that pulls the same images.
resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = {
    for pair in flatten([
      for repo_key, readers in var.readers : [
        for index, member in readers : {
          key    = "${repo_key}-${index}"
          repo   = repo_key
          member = member
        }
      ]
    ]) : pair.key => pair
  }

  project    = var.project_id
  location   = var.region
  repository = each.value.repo
  role       = "roles/artifactregistry.reader"
  member     = each.value.member

  depends_on = [
    google_artifact_registry_repository.standard,
    google_artifact_registry_repository.remote,
  ]
}
