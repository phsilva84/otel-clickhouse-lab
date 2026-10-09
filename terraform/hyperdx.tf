# Segredo com a senha do usuario ClickHouse "hyperdx".
# Somente o container: o valor NAO passa pelo state (ver hyperdx/README.md).
resource "google_secret_manager_secret" "hyperdx_password" {
  secret_id = "${var.name_prefix}-hyperdx-password"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

output "hyperdx_secret" {
  value = google_secret_manager_secret.hyperdx_password.secret_id
}
