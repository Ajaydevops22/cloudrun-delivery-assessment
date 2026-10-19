mock_provider "google" {}

variables {
  project_id   = "test-project"
  region       = "us-central1"
  environment  = "dev"
  service_name = "demo-svc"
  image        = "us-central1-docker.pkg.dev/test-project/apps/demo@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

run "defaults_block_direct_internet_access" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "Default ingress must allow only the internal load balancer path."
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "No invoker bindings may exist unless explicitly requested."
  }
}

run "dedicated_service_account_per_environment" {
  command = plan

  assert {
    condition     = google_service_account.runtime.account_id == "demo-svc-dev"
    error_message = "Runtime service account must be dedicated and named per service and environment."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.name == "demo-svc-dev"
    error_message = "Service name must include the environment."
  }
}

run "secrets_get_scoped_accessor_role_only" {
  command = plan

  variables {
    secret_env = {
      DB_PASSWORD = {
        secret_id = "db-password"
        version   = "3"
      }
    }
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.runtime_secret_access["DB_PASSWORD"].role == "roles/secretmanager.secretAccessor"
    error_message = "Runtime identity must get only secretAccessor on the referenced secret."
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.runtime_secret_access["DB_PASSWORD"].secret_id == "db-password"
    error_message = "Secret access must be scoped to the specific secret."
  }
}

run "rejects_public_invoker" {
  command = plan

  variables {
    invoker_members = ["allUsers"]
  }

  expect_failures = [var.invoker_members]
}

run "rejects_latest_image_tag" {
  command = plan

  variables {
    image = "us-central1-docker.pkg.dev/test-project/apps/demo:latest"
  }

  expect_failures = [var.image]
}
