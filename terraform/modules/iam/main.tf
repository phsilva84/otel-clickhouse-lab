resource "google_service_account" "collector" {
  account_id   = "${var.name_prefix}-collector"
  display_name = "OTel Collector (lab)"
}

# Failover: escrita (e leitura p/ replay) no bucket
resource "google_storage_bucket_iam_member" "bucket" {
  bucket = var.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.collector.email}"
}

# Recovery: leitura da subscription
resource "google_pubsub_subscription_iam_member" "sub" {
  subscription = var.subscription_name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.collector.email}"
}

# Segredo: só o container; o valor NÃO passa pelo state (ver comando no README/resposta)
resource "google_secret_manager_secret" "clickhouse_password" {
  secret_id = "${var.name_prefix}-clickhouse-password"
  labels    = var.labels
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  secret_id = google_secret_manager_secret.clickhouse_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.collector.email}"
}

# Mínimo operacional da VM
resource "google_project_iam_member" "logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "metricwriter" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.collector.email}"
}
