module "service" {
  source = "../../modules/cloud_run"

  project_id      = var.project_id
  region          = var.region
  environment     = "prod"
  service_name    = "cloudrun-svc"
  image           = var.image
  invoker_members = var.invoker_members

  cpu           = "2"
  memory        = "1Gi"
  min_instances = 1
  max_instances = 10

  deletion_protection = true
}
