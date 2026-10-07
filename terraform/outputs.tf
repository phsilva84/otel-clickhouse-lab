output "vm_external_ip" { value = module.compute.external_ip }
output "grafana_url"    { value = "http://${module.compute.external_ip}:3000" }
output "otlp_grpc"      { value = "${module.compute.external_ip}:4317" }
output "otlp_http"      { value = "http://${module.compute.external_ip}:4318" }
output "failover_bucket" { value = module.storage.bucket_name }
output "pubsub_topic"   { value = module.messaging.topic_name }
output "pubsub_subscription" { value = module.messaging.subscription_name }
output "collector_sa"   { value = module.iam.service_account_email }
output "clickhouse_secret" { value = module.iam.clickhouse_secret_id }
output "ssh_command" {
  value = "gcloud compute ssh ${module.compute.instance_name} --zone ${var.zone} --project ${var.project_id}"
}
