# Vaultwarden on Cloud Run.
#
# The same service as the Kubernetes variant, with one difference that changes
# everything else: Cloud Run has no persistent local disk. Every design choice
# below follows from that single constraint.

# SQLite is not an option here. Cloud Run's filesystem is per-instance and
# disappears when the instance does, so the database has to live outside the
# container. This is not a preference between two databases; on this platform
# one of them cannot exist.
resource "google_sql_database_instance" "vault" {
  name             = "${var.name}-db"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_autoresize   = true

    ip_configuration {
      # No public IP. The service reaches it over the VPC, which means the
      # database is not addressable from the internet at all.
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "07:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 30
      }
    }
  }

  # Deleting the database that holds every credential should take more than a
  # terraform destroy typed in the wrong directory.
  deletion_protection = true
}

resource "google_sql_database" "vault" {
  name     = "vaultwarden"
  instance = google_sql_database_instance.vault.name
  project  = var.project_id
}

# The signing keys are the subtle part of running this on Cloud Run.
#
# Vaultwarden generates an RSA key on first boot and uses it to sign session
# tokens. On a platform with a persistent disk the key is written once and
# reused. On Cloud Run each new instance starts with an empty filesystem, so
# each one would generate a different key, and a token signed by one instance
# would be rejected by the next. The symptom is users being logged out at
# random, which reads like a bug in the client rather than a storage decision.
#
# The key is therefore generated once, out of band, and mounted from Secret
# Manager. This resource holds the container; the version is created outside
# Terraform so the key itself never passes through state.
resource "google_secret_manager_secret" "rsa_key" {
  secret_id = "${var.name}-rsa-key"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "db_url" {
  secret_id = "${var.name}-database-url"
  project   = var.project_id
  replication {
    auto {}
  }
}

# Attachments and Sends are written to disk by the application and would be
# lost on every instance recycle. A bucket mounted into the container keeps
# them, at the cost of the latency difference between a disk and an API.
resource "google_storage_bucket" "data" {
  name                        = "${var.project_id}-${var.name}-data"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

# One identity for this service, holding only what it uses. The default compute
# service account is shared by everything in the project and carries far more.
resource "google_service_account" "vault" {
  account_id   = "sa-${var.name}"
  display_name = "Vaultwarden runtime"
  project      = var.project_id
}

resource "google_project_iam_member" "sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.vault.email}"
}

# Access is granted per secret rather than at the project level, so the service
# can read its own two secrets and no others.
resource "google_secret_manager_secret_iam_member" "rsa_key" {
  secret_id = google_secret_manager_secret.rsa_key.id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vault.email}"
}

resource "google_secret_manager_secret_iam_member" "db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vault.email}"
}

resource "google_storage_bucket_iam_member" "data" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vault.email}"
}

resource "google_cloud_run_v2_service" "vault" {
  name     = var.name
  project  = var.project_id
  location = var.region

  # Only a load balancer reaches this service. Cloud Run's default of allowing
  # all traffic would put the vault's login page directly on the internet with
  # no layer in front of it.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  deletion_protection = true

  template {
    service_account = google_service_account.vault.email

    scaling {
      # Exactly one instance, and this is a decision rather than a default.
      #
      # Scaling to zero would put a cold start in front of someone reaching for
      # a password, which is when they are least willing to wait. Scaling past
      # one is worse: Vaultwarden's WebSocket notifications are held per
      # instance, so a second instance silently stops syncing vault changes to
      # clients connected to the first.
      min_instance_count = 1
      max_instance_count = 1
    }

    # Cloud SQL is reached over its private IP through this VPC connection, so
    # there is no proxy sidecar. That absence is a decision, not an omission.
    vpc_access {
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnetwork_id
      }
      # Only private ranges leave through the VPC. The service still needs the
      # internet for SMTP, and sending all traffic through the VPC would need a
      # NAT that exists for no other reason.
      egress = "PRIVATE_RANGES_ONLY"
    }

    volumes {
      name = "rsa-key"
      secret {
        secret = google_secret_manager_secret.rsa_key.secret_id
        items {
          version = "latest"
          path    = "rsa_key.pem"
        }
      }
    }

    volumes {
      name = "attachments"
      gcs {
        bucket    = google_storage_bucket.data.name
        read_only = false
      }
    }

    containers {
      # Resolve and pin the digest before applying. See the note in the
      # Kubernetes manifest: a digest copied from a document pins nothing.
      image = var.image

      # ADMIN_TOKEN is absent here for the same reason it is absent from the
      # Kubernetes variant. See ADR 6.
      env {
        name  = "ROCKET_PORT"
        value = "8080"
      }
      env {
        name  = "SIGNUPS_ALLOWED"
        value = "false"
      }
      env {
        name  = "DOMAIN"
        value = var.domain
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "rsa-key"
        mount_path = "/data"
      }
      volume_mounts {
        name       = "attachments"
        mount_path = "/data/attachments"
      }

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # The instance stays warm between requests. Without this the CPU is
        # throttled once a response is sent, and the background jobs that expire
        # sessions and send notifications run erratically or not at all.
        cpu_idle = false
      }

      startup_probe {
        http_get {
          path = "/alive"
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 6
      }
    }
  }
}
