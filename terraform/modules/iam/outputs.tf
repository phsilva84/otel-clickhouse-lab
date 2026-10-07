output "service_account_email" { value = google_service_account.collector.email }
output "clickhouse_secret_id" { value = google_secret_manager_secret.clickhouse_password.secret_id }
