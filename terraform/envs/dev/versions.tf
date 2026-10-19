terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state in GCS (versioned bucket, native state locking).
  # Bucket is supplied at init time so no real names live in code:
  #   terraform init -backend-config="bucket=<state-bucket>"
  backend "gcs" {
    prefix = "cloudrun/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
