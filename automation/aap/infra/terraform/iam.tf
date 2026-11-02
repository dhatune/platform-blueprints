# Identity of aap-01. Used keyless by the GCP inventory plugin (metadata server).
resource "google_service_account" "aap_inventory" {
  account_id   = "sa-aap-inventory"
  display_name = "AAP PoC - inventory and platform host"
}

resource "google_project_iam_member" "aap_inventory" {
  for_each = toset([
    "roles/compute.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.aap_inventory.email}"
}

# Identity of managed nodes: write compliance evidence and logs only.
resource "google_service_account" "aap_nodes" {
  account_id   = "sa-aap-nodes"
  display_name = "AAP PoC - managed nodes"
}

resource "google_project_iam_member" "aap_nodes_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.aap_nodes.email}"
}

# Bucket-scoped write access to evidence (no read, no delete).
resource "google_storage_bucket_iam_member" "evidence_writers" {
  for_each = {
    inventory = google_service_account.aap_inventory.email
    nodes     = google_service_account.aap_nodes.email
  }
  bucket = google_storage_bucket.evidence.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${each.value}"
}
