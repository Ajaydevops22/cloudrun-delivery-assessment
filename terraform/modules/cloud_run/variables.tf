variable "project_id" {
  description = "GCP project that hosts the service."
  type        = string
}

variable "region" {
  description = "Cloud Run region."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "service_name" {
  description = "Base service name (3-22 chars, lowercase letters, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-22 chars, start with a letter, and use lowercase letters, digits or hyphens."
  }
}

variable "image" {
  description = "Container image reference, preferably pinned by digest (repo/name@sha256:...)."
  type        = string

  validation {
    condition     = !endswith(var.image, ":latest")
    error_message = "Do not deploy :latest. Use a commit-SHA tag or an image digest."
  }
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "timeout_seconds" {
  type    = number
  default = 60

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "timeout_seconds must be between 1 and 3600."
  }
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 3

  validation {
    condition     = var.max_instances >= 1
    error_message = "max_instances must be at least 1."
  }
}

variable "ingress" {
  description = "Who can reach the service. Default blocks direct internet access and allows only a Google load balancer."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "Invalid ingress value."
  }
}

variable "invoker_members" {
  description = "IAM members allowed to invoke the service. Empty means nobody (no public access)."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.invoker_members, "allUsers") && !contains(var.invoker_members, "allAuthenticatedUsers")
    error_message = "Public invokers (allUsers, allAuthenticatedUsers) are not allowed."
  }
}

variable "env_vars" {
  description = "Plain, non-secret environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Env var name => Secret Manager reference. Only references, never secret values."
  type = map(object({
    secret_id = string
    version   = string
  }))
  default = {}
}

variable "deletion_protection" {
  type    = bool
  default = true
}
