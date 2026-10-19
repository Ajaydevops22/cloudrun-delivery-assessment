output "service_name" {
  value = google_cloud_run_v2_service.this.name
}

output "service_url" {
  value = google_cloud_run_v2_service.this.uri
}

output "service_account_email" {
  value = google_service_account.runtime.email
}

output "latest_ready_revision" {
  value = google_cloud_run_v2_service.this.latest_ready_revision
}

output "ingress" {
  value = google_cloud_run_v2_service.this.ingress
}
