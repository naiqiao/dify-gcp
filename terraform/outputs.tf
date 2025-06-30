output "instance_external_ip" {
  description = "The external IP address of the Dify instance"
  value       = google_compute_address.dify_static_ip.address
}

output "instance_name" {
  description = "The name of the Dify compute instance"
  value       = google_compute_instance.dify_instance.name
}

output "instance_zone" {
  description = "The zone of the Dify compute instance"
  value       = google_compute_instance.dify_instance.zone
}

output "db_connection_name" {
  description = "The connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.dify_db.connection_name
}

output "db_private_ip" {
  description = "The private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.dify_db.private_ip_address
}

output "db_name" {
  description = "The name of the database"
  value       = google_sql_database.dify_database.name
}

output "db_username" {
  description = "The database username"
  value       = google_sql_user.dify_db_user.name
}

output "db_password" {
  description = "The database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_host" {
  description = "The host address of the Redis instance"
  value       = google_redis_instance.dify_redis.host
}

output "redis_port" {
  description = "The port of the Redis instance"
  value       = google_redis_instance.dify_redis.port
}

output "storage_bucket_name" {
  description = "The name of the storage bucket"
  value       = google_storage_bucket.dify_storage.name
}

output "storage_bucket_url" {
  description = "The URL of the storage bucket"
  value       = google_storage_bucket.dify_storage.url
}

output "service_account_email" {
  description = "The email of the service account"
  value       = google_service_account.dify_service_account.email
}

output "load_balancer_ip" {
  description = "The IP address of the load balancer (if domain is configured)"
  value       = var.domain != "" ? google_compute_global_address.dify_lb_ip[0].address : null
}

output "ssl_certificate_name" {
  description = "The name of the SSL certificate (if domain is configured)"
  value       = var.domain != "" ? google_compute_managed_ssl_certificate.dify_ssl_cert[0].name : null
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.dify_network.name
}

output "subnet_name" {
  description = "The name of the subnet"
  value       = google_compute_subnetwork.dify_subnet.name
}

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

output "access_url" {
  description = "The URL to access Dify"
  value       = var.domain != "" ? "https://${var.domain}" : "http://${google_compute_address.dify_static_ip.address}"
} 