locals { tag = "${var.name_prefix}-vm" }

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
}

# OTLP gRPC/HTTP + Grafana: somente do(s) seu(s) IP(s)
resource "google_compute_firewall" "app_ingress" {
  name          = "${var.name_prefix}-allow-app"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = var.allowed_cidrs
  target_tags   = [local.tag]
  allow {
    protocol = "tcp"
    ports    = ["4317", "4318", "3000"]
  }
}

resource "google_compute_firewall" "ssh_ingress" {
  name          = "${var.name_prefix}-allow-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = var.allowed_cidrs
  target_tags   = [local.tag]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
