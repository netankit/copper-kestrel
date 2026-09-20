resource "google_container_cluster" "primary" {
  name     = "${var.env}-search"
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }
}

resource "google_container_node_pool" "search" {
  name     = "search-pool"
  cluster  = google_container_cluster.primary.name
  location = var.zone

  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-ssd"
    local_ssd_count = var.local_ssd_count

    labels = {
      workload = "search"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

resource "google_compute_firewall" "search_internal" {
  name    = "${var.env}-search-internal"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["10.0.0.0/8"]
}
