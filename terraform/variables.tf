variable "project_id" {
  type        = string
  description = "GCP project"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "Zone the search cluster runs in"
}

variable "node_count" {
  type    = number
  default = 6
}

variable "machine_type" {
  type    = string
  default = "n2-standard-16"
}

variable "disk_size_gb" {
  type    = number
  default = 500
}

variable "local_ssd_count" {
  type        = number
  default     = 2
  description = "375 GB each"
}
