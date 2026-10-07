terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0" # CONFIRMAR/fixar a versão que você validou com `terraform init`
    }
  }

  # Backend remoto (opcional, recomendado p/ GitHub Actions). Crie o bucket antes (fora deste TF).
  # backend "gcs" {
  #   bucket = "SEU-BUCKET-TFSTATE"
  #   prefix = "otel-lab"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
