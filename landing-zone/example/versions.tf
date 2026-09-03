terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }

  # State lives in a bucket, versioned, with a lifecycle rule. Local state on a
  # laptop is a single point of failure and cannot be reviewed.
  #
  # backend "gcs" {
  #   bucket = "example-tfstate"
  #   prefix = "landing-zone"
  # }
}

provider "google" {
  region = var.region

  # Quota and billing are attributed to one project explicitly. Without this,
  # API calls are charged against whichever project the credential happens to
  # resolve to, which fails in confusing ways once more than one project exists.
  billing_project       = var.quota_project
  user_project_override = true
}
