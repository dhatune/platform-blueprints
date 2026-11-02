# Compliance and audit evidence (OpenSCAP reports, job audit exports).
resource "google_storage_bucket" "evidence" {
  name                        = "${var.project_id}-evidence"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  # PoC only: allow `make down` to remove it. In production use a retention policy instead.
  force_destroy = true

  versioning {
    enabled = true
  }
}
