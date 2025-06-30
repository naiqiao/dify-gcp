variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for compute resources"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "The machine type for the compute instance"
  type        = string
  default     = "e2-standard-4"
}

variable "db_tier" {
  description = "The tier for the Cloud SQL instance"
  type        = string
  default     = "db-g1-small"
}

variable "redis_memory_size_gb" {
  description = "The memory size in GB for the Redis instance"
  type        = number
  default     = 1
}

variable "domain" {
  description = "Custom domain for Dify (optional)"
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Admin email for SSL certificate (required if domain is set)"
  type        = string
  default     = ""
}

variable "dify_version" {
  description = "Dify version to deploy"
  type        = string
  default     = "latest"
}

variable "ssh_username" {
  description = "SSH username for the compute instance"
  type        = string
  default     = "dify"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {
    Environment = "production"
    Application = "dify"
  }
} 