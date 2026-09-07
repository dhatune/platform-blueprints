# A cluster on the shared network.
#
# The network belongs to the host project and the cluster belongs to this one,
# which is the arrangement the rest of this landing zone is built around. It
# costs one grant that is easy to miss and is described below.

# The service agent has to exist before it can be granted anything. Terraform
# will otherwise try to bind a principal the platform has not created yet, and
# the error names a service account nobody wrote.
resource "google_project_service_identity" "container" {
  provider = google-beta
  project  = var.project_id
  service  = "container.googleapis.com"
}

# The grant that makes a cluster on somebody else's network possible.
#
# It is made in the host project, not here, and without it cluster creation
# fails after several minutes with a message about the subnetwork rather than
# about permission.
resource "google_project_iam_member" "host_agent" {
  project    = var.host_project_id
  role       = "roles/container.hostServiceAgentUser"
  member     = "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
  depends_on = [google_project_service_identity.container]
}

resource "google_container_cluster" "this" {
  provider = google-beta

  name     = var.name
  project  = var.project_id
  location = var.location

  network    = var.network_id
  subnetwork = var.subnet_id

  # The default pool is replaced rather than configured, because its node
  # settings cannot be changed in place afterwards.
  remove_default_node_pool = true
  initial_node_count       = 1

  # A lab is meant to be destroyed. Anything long-lived should set this.
  deletion_protection = var.deletion_protection

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_range_name
    services_secondary_range_name = var.service_range_name
  }

  # Both are cluster capabilities rather than things installed later, and
  # neither can be added by deploying a controller afterwards.
  #
  # Without the Gateway API the cluster has no gatewayclass resource at all, so
  # nothing can define an entry point. Without Workload Identity a pod cannot
  # hold a cloud identity, so anything that changes DNS records or answers an
  # ACME challenge would need a key instead, which this estate forbids. ADR 5.
  #
  # Leaving them out produces a cluster that runs workloads perfectly and that
  # nobody outside can reach. The gap is invisible until you try.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Declared rather than left at the default, because the default enables every
  # billable metric collector the platform offers and the charge appears under
  # a name that does not mention the cluster.
  monitoring_config {
    enable_components = var.monitoring_components
  }

  depends_on = [google_project_iam_member.host_agent]
}

# Interruptible capacity for everything whose restart is free.
resource "google_container_node_pool" "this" {
  provider = google-beta

  name     = "default"
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb

    # Interruptible capacity. Correct for anything whose restart is free, and
    # wrong for work that is recorded as started. ADR 8.
    spot = var.spot

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # The node runs the metadata server that hands pods their identity.
    # Enabling the pool without this leaves Workload Identity configured on the
    # cluster and not working on the nodes, which fails as a timeout rather
    # than as a permission error.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# Capacity for workloads that must not be evicted.
#
# ADR 8: being restartable and being interruptible are different properties.
# A workload with no local state restarts safely, and that says nothing about
# what happens when it is evicted halfway through work it has already recorded
# as started.
#
# The pool is labelled and tainted rather than merely labelled. A label alone
# lets anything land here that did not ask not to, which fills the expensive
# nodes with work that belongs on the cheap ones.
resource "google_container_node_pool" "stateful" {
  provider = google-beta
  count    = var.stateful_node_count > 0 ? 1 : 0

  name     = "stateful"
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name

  node_count = var.stateful_node_count

  node_config {
    machine_type = var.stateful_machine_type
    disk_size_gb = var.disk_size_gb
    spot         = false

    labels = {
      "node-role" = "stateful"
    }

    taint {
      key    = "workload"
      value  = "stateful"
      effect = "NO_SCHEDULE"
    }

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
