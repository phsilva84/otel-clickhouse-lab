variable "project_id" {
  description = "ID do projeto GCP do lab"
  type        = string
}

variable "region" {
  description = "Região Always Free: us-west1, us-central1 ou us-east1"
  type        = string
  default     = "us-central1"
  validation {
    condition     = contains(["us-west1", "us-central1", "us-east1"], var.region)
    error_message = "Fora do Always Free do e2-micro. Use us-west1, us-central1 ou us-east1."
  }
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "name_prefix" {
  type    = string
  default = "otel-lab"
}

variable "allowed_cidrs" {
  description = "Seu IP público em /32 (ex.: [\"X.X.X.X/32\"]). Nunca 0.0.0.0/0."
  type        = list(string)
  validation {
    condition     = length(var.allowed_cidrs) > 0 && !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "Informe ao menos um CIDR e não use 0.0.0.0/0."
  }
}

variable "subnet_cidr" {
  description = "PLACEHOLDER: confirme que não conflita com suas redes."
  type        = string
  default     = "10.10.0.0/24"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "disk_size_gb" {
  description = "Máx. 30 GB no Always Free (pd-standard)"
  type        = number
  default     = 30
}

variable "swap_size_gb" {
  type    = number
  default = 2
}

variable "failover_ttl_days" {
  description = "TTL do bucket de failover (prod=3, hml=1, lab=1)"
  type        = number
  default     = 1
}

variable "repo_url" {
  description = "URL HTTPS do repo GitHub (público, ou com token via Secret Manager — fora do escopo)"
  type        = string
}

variable "repo_ref" {
  type    = string
  default = "main"
}

variable "labels" {
  type    = map(string)
  default = { env = "lab", app = "otel-clickhouse" }
}
