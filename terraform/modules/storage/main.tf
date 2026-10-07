resource "google_storage_bucket" "failover" {
  name                        = "${var.name_prefix}-failover-${var.project_id}"
  location                    = var.location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # lab: permite destroy com objetos
  labels                      = var.labels

  lifecycle_rule {
    condition {
      age = var.ttl_days
    }
    action {
      type = "Delete"
    }
  }
}
