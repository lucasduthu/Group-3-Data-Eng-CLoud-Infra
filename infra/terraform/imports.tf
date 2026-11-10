# Adopter l'existant, ne pas recréer. Ignorés une fois appliqués.
import {
  to = google_storage_bucket.bronze
  id = "albert-de-msc2-26-g03-bronze"
}

import {
  to = google_bigquery_dataset.bronze
  id = "projects/data-engineering-i1/datasets/g03_bronze"
}

import {
  to = google_bigquery_dataset.warehouse
  id = "projects/data-engineering-i1/datasets/g03_warehouse"
}

import {
  to = google_bigquery_dataset.analytics
  id = "projects/data-engineering-i1/datasets/g03_analytics"
}
