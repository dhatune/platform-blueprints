# Folder hierarchy.
#
#   organisation
#   └── root
#       ├── shared      networking, CI/CD, observability
#       └── <product>   one per product, each with its own environments
#
# Shared is separated from the products because the resources inside it are
# owned by whoever runs the platform, not by whoever builds a product. Keeping
# that boundary in the hierarchy means it can be enforced with IAM instead of
# with convention.

resource "google_folder" "root" {
  display_name        = var.root_folder_name
  parent              = "organizations/${var.organization_id}"
  deletion_protection = true
}

resource "google_folder" "shared" {
  display_name        = "shared"
  parent              = google_folder.root.name
  deletion_protection = true
}

resource "google_folder" "product" {
  for_each = toset(var.product_folders)

  display_name        = each.value
  parent              = google_folder.root.name
  deletion_protection = true
}
