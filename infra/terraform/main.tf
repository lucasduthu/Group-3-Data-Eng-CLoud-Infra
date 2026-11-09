resource "google_storage_bucket" "bronze" {
  name                        = "albert-de-msc2-26-g03-bronze"
  location                    = "EUROPE-WEST1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false

  # Lifecycle du step 2 (infra/lifecycle.json)
  lifecycle_rule {
    condition {
      age                   = 90
      matches_prefix        = ["bronze/export/"]
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age            = 90
      matches_prefix = ["bronze/_dlq/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_bigquery_dataset" "bronze" {
  dataset_id = "g03_bronze"
  location   = "europe-west1"
}

resource "google_bigquery_dataset" "warehouse" {
  dataset_id = "g03_warehouse"
  location   = "europe-west1"
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id = "g03_analytics"
  location   = "europe-west1"
}

# Pas de google_service_account ni de google_storage_bucket_iam_member : le service
# account Airbyte n'a jamais existé (step 3, route 3) et nos comptes n'ont ni
# iam.serviceAccounts.create ni iam.serviceAccounts.list sur data-engineering-i1.
