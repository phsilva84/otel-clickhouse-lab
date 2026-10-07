locals {
  apis = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.key
  disable_on_destroy = false
}

module "network" {
  source        = "./modules/network"
  name_prefix   = var.name_prefix
  region        = var.region
  subnet_cidr   = var.subnet_cidr
  allowed_cidrs = var.allowed_cidrs
  depends_on    = [google_project_service.apis]
}

module "storage" {
  source      = "./modules/storage"
  name_prefix = var.name_prefix
  project_id  = var.project_id
  location    = var.region
  ttl_days    = var.failover_ttl_days
  labels      = var.labels
  depends_on  = [google_project_service.apis]
}

module "messaging" {
  source      = "./modules/messaging"
  name_prefix = var.name_prefix
  project_id  = var.project_id
  bucket_name = module.storage.bucket_name
  labels      = var.labels
  depends_on  = [google_project_service.apis]
}

module "iam" {
  source            = "./modules/iam"
  name_prefix       = var.name_prefix
  project_id        = var.project_id
  bucket_name       = module.storage.bucket_name
  subscription_name = module.messaging.subscription_name
  labels            = var.labels
  depends_on        = [google_project_service.apis]
}

module "compute" {
  source                = "./modules/compute"
  name_prefix           = var.name_prefix
  zone                  = var.zone
  machine_type          = var.machine_type
  disk_size_gb          = var.disk_size_gb
  swap_size_gb          = var.swap_size_gb
  subnet_self_link      = module.network.subnet_self_link
  network_tag           = module.network.network_tag
  service_account_email = module.iam.service_account_email
  repo_url              = var.repo_url
  repo_ref              = var.repo_ref
  project_id            = var.project_id
  bucket_name           = module.storage.bucket_name
  subscription_name     = module.messaging.subscription_name
  secret_id             = module.iam.clickhouse_secret_id
  labels                = var.labels
}
