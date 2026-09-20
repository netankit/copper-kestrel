terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "acme-tfstate"
    prefix = "search"
  }
}

provider "google" {
  project = var.project_id
  zone    = var.zone
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "node_pool_size" {
  value = google_container_node_pool.search.node_count
}
