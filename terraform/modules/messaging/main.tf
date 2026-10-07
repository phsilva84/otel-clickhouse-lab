# Notificação nativa GCS -> Pub/Sub (OBJECT_FINALIZE). Eventarc não tem destino "VM";
# para o Recovery Collector (pull) o caminho direto é o mais simples e barato.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

resource "google_pubsub_topic" "recovery" {
  name   = "${var.name_prefix}-failover-events"
  labels = var.labels
}

resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  topic  = google_pubsub_topic.recovery.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_notification" "on_finalize" {
  bucket         = var.bucket_name
  topic          = google_pubsub_topic.recovery.id
  payload_format = "JSON_API_V1"
  event_types    = ["OBJECT_FINALIZE"]
  depends_on     = [google_pubsub_topic_iam_member.gcs_publisher]
}

resource "google_pubsub_subscription" "recovery" {
  name                       = "${var.name_prefix}-recovery-sub"
  topic                      = google_pubsub_topic.recovery.id
  ack_deadline_seconds       = 60
  message_retention_duration = "86400s"
  labels                     = var.labels

  expiration_policy {
    ttl = "" # nunca expira
  }
}
