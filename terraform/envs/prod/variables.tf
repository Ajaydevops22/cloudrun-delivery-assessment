variable "project_id" {
  description = "GCP project for this environment."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "image" {
  description = "Image reference, pinned by digest or commit SHA tag."
  type        = string
}

variable "invoker_members" {
  type    = list(string)
  default = []
}
