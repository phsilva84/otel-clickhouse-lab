resource "google_compute_instance" "lab" {
  name         = "${var.name_prefix}-vm"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = [var.network_tag]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.disk_size_gb
      type  = "pd-standard" # SSD sai do Always Free
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    access_config {
      network_tier = "STANDARD" # Premium sai do free
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"] # permissões reais vêm do IAM da SA
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      repo_url          = var.repo_url
      repo_ref          = var.repo_ref
      swap_size_gb      = var.swap_size_gb
      project_id        = var.project_id
      bucket_name       = var.bucket_name
      subscription_name = var.subscription_name
      secret_id         = var.secret_id
    })
  }

  allow_stopping_for_update = true
}
