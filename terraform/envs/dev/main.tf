module "service" {
  source = "../../modules/cloud_run"

  project_id      = var.project_id
  region          = var.region
  environment     = "dev"
  service_name    = "cloudrun-svc"
  image           = var.image
  invoker_members = var.invoker_members

  cpu           = "1"
  memory        = "512Mi"
  min_instances = 0
  max_instances = 2

  deletion_protection = false
}
