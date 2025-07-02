# Configure the Google Cloud Provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com", 
    "redis.googleapis.com",
    "storage.googleapis.com",
    "servicenetworking.googleapis.com",
    "dns.googleapis.com",
    "certificatemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Random password for database
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# VPC Network
resource "google_compute_network" "dify_network" {
  name                    = "${var.project_id}-dify-network"
  auto_create_subnetworks = false
  description             = "VPC network for Dify deployment"

  depends_on = [google_project_service.required_apis]
}

# Subnet
resource "google_compute_subnetwork" "dify_subnet" {
  name          = "${var.project_id}-dify-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.dify_network.id
}

# Firewall rules
resource "google_compute_firewall" "allow_http" {
  name    = "${var.project_id}-dify-allow-http"
  network = google_compute_network.dify_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dify-web"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_id}-dify-allow-ssh"
  network = google_compute_network.dify_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dify-web"]
}

# Static IP for the instance
resource "google_compute_address" "dify_static_ip" {
  name   = "${var.project_id}-dify-static-ip"
  region = var.region
}

# Compute Engine instance
resource "google_compute_instance" "dify_instance" {
  name         = "${var.project_id}-dify-instance"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["dify-web"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.dify_network.id
    subnetwork = google_compute_subnetwork.dify_subnet.id
    access_config {
      nat_ip = google_compute_address.dify_static_ip.address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${file(pathexpand(var.ssh_public_key_path))}"
  }

  metadata_startup_script = file("${path.module}/startup-script.sh")

  service_account {
    email = google_service_account.dify_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [
    google_sql_database_instance.dify_db,
    google_redis_instance.dify_redis
  ]
}

# Service Account for the instance
resource "google_service_account" "dify_service_account" {
  account_id   = "${var.project_id}-dify-sa"
  display_name = "Dify Service Account"
  description  = "Service account for Dify deployment"
}

# IAM binding for service account
resource "google_project_iam_member" "dify_service_account_bindings" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/storage.admin",
    "roles/redis.editor"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dify_service_account.email}"
}

# Cloud SQL Database
resource "google_sql_database_instance" "dify_db" {
  name             = "${var.project_id}-dify-db"
  database_version = "POSTGRES_15"
  region           = var.region
  deletion_protection = false

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 20

    backup_configuration {
      enabled    = true
      start_time = "03:00"
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.dify_network.id
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Database user
resource "google_sql_user" "dify_db_user" {
  name     = "dify"
  instance = google_sql_database_instance.dify_db.name
  password = random_password.db_password.result
}

# Database
resource "google_sql_database" "dify_database" {
  name     = "dify"
  instance = google_sql_database_instance.dify_db.name
}

# Private service networking connection
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.project_id}-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.dify_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.dify_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Redis instance
resource "google_redis_instance" "dify_redis" {
  name           = "${var.project_id}-dify-redis"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  tier           = "BASIC"
  redis_version  = "REDIS_7_0"

  authorized_network = google_compute_network.dify_network.id

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Storage bucket for file uploads
resource "google_storage_bucket" "dify_storage" {
  name          = "${var.project_id}-dify-storage"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

# IAM binding for storage bucket
resource "google_storage_bucket_iam_member" "dify_storage_admin" {
  bucket = google_storage_bucket.dify_storage.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.dify_service_account.email}"
}

# Load balancer (if domain is provided)
resource "google_compute_global_address" "dify_lb_ip" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.project_id}-dify-lb-ip"
}

resource "google_compute_backend_service" "dify_backend" {
  count                           = var.domain != "" ? 1 : 0
  name                            = "${var.project_id}-dify-backend"
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = 30
  connection_draining_timeout_sec = 30

  backend {
    group = google_compute_instance_group.dify_instance_group[0].id
  }

  health_checks = [google_compute_health_check.dify_health_check[0].id]
}

resource "google_compute_instance_group" "dify_instance_group" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.project_id}-dify-instance-group"
  zone  = var.zone

  instances = [google_compute_instance.dify_instance.id]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_health_check" "dify_health_check" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.project_id}-dify-health-check"

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

resource "google_compute_url_map" "dify_url_map" {
  count           = var.domain != "" ? 1 : 0
  name            = "${var.project_id}-dify-url-map"
  default_service = google_compute_backend_service.dify_backend[0].id
}

resource "google_compute_target_https_proxy" "dify_https_proxy" {
  count   = var.domain != "" ? 1 : 0
  name    = "${var.project_id}-dify-https-proxy"
  url_map = google_compute_url_map.dify_url_map[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.dify_ssl_cert[0].id]
}

resource "google_compute_managed_ssl_certificate" "dify_ssl_cert" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.project_id}-dify-ssl-cert"

  managed {
    domains = [var.domain]
  }
}

resource "google_compute_global_forwarding_rule" "dify_https_forwarding_rule" {
  count      = var.domain != "" ? 1 : 0
  name       = "${var.project_id}-dify-https-forwarding-rule"
  target     = google_compute_target_https_proxy.dify_https_proxy[0].id
  port_range = "443"
  ip_address = google_compute_global_address.dify_lb_ip[0].address
}

resource "google_compute_global_forwarding_rule" "dify_http_forwarding_rule" {
  count      = var.domain != "" ? 1 : 0
  name       = "${var.project_id}-dify-http-forwarding-rule"
  target     = google_compute_target_http_proxy.dify_http_proxy[0].id
  port_range = "80"
  ip_address = google_compute_global_address.dify_lb_ip[0].address
}

resource "google_compute_target_http_proxy" "dify_http_proxy" {
  count   = var.domain != "" ? 1 : 0
  name    = "${var.project_id}-dify-http-proxy"
  url_map = google_compute_url_map.dify_http_redirect[0].id
}

resource "google_compute_url_map" "dify_http_redirect" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.project_id}-dify-http-redirect"

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    https_redirect         = true
    strip_query            = false
  }
} 