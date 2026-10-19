# Cloud Run delivery pattern (Docker, Terraform, GitHub Actions)

A small, production-shaped delivery pattern for a stateless HTTP service on Google Cloud Run. No Google Cloud account was used: everything below was validated locally, in GitHub Actions, or with a mocked Terraform provider. Items that were not run are listed in "Implemented vs conceptual".

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | Flask service with `/health`, `/ready`, `/version`, and tests |
| `Dockerfile`, `.dockerignore` | Multi-stage, non-root image |
| `terraform/modules/cloud_run` | Reusable Cloud Run module and `terraform test` file |
| `terraform/envs/dev`, `terraform/envs/prod` | Two environments calling the same module |
| `.github/workflows/` | `pr-checks.yml`, `release.yml`, `rollback.yml` |
| `scripts/pin-actions.ps1` | Pins GitHub Actions to commit SHAs |
| `docs/` | Incident runbook, HA design, scan notes, evidence |

## Prerequisites

Docker, Terraform 1.7 or newer, Python 3.12, Trivy. No cloud credentials are needed for anything below.

## Setup and validation (commands I ran)

```
# App tests
py -m venv app/.venv
app/.venv/Scripts/python.exe -m pip install -r app/requirements-dev.txt
app/.venv/Scripts/python.exe -m pytest -v app

# Container
docker build -t cloudrun-svc:local --build-arg GIT_SHA=local .
docker run -d --name svc -p 8080:8080 cloudrun-svc:local
curl.exe http://localhost:8080/health
docker exec svc id            # uid=10001 (non-root)
trivy image --severity HIGH,CRITICAL cloudrun-svc:local

# Terraform (no credentials, mocked provider)
terraform -chdir=terraform fmt -recursive -check
terraform -chdir=terraform/modules/cloud_run init -backend=false
terraform -chdir=terraform/modules/cloud_run validate
terraform -chdir=terraform/modules/cloud_run test
```

Output is saved in `docs/evidence/`:

- `app-tests.txt`: 3 tests passed
- `docker-health.txt`: health, ready and version responses, and `uid=10001`
- `trivy-full.txt`, `trivy-fixable.txt` and `docs/security-scan.md`: scan results and accepted findings
- `terraform-test.txt`: 5 test runs passed; `terraform-validate-dev.txt` and `terraform-validate-prod.txt`: both environments valid
- `pr-checks-green.png`: all three PR checks green
- `release-run.png`: release workflow on `main` (build job ran, cloud jobs skipped)

## Container

Multi-stage build on `python:3.12-slim`. The runtime image has only the app and two dependencies, runs as uid 10001, exposes only port 8080, and contains no secrets. Trivy found 0 CRITICAL and 44 HIGH findings, all without a vendor fix yet; they are accepted and explained in `docs/security-scan.md`. The CI gate fails on CRITICAL or fixable HIGH findings.

## Terraform

- Module inputs: service name, project, region, environment, image, CPU, memory, timeout, concurrency, min and max instances, ingress, invoker members, env vars, secret references.
- Dedicated runtime service account per service and environment, with only `secretAccessor` on the specific secrets it references.
- Ingress default is `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`, so the `run.app` URL is not reachable directly. A load balancer can be added later without changing the module, and direct access stays blocked.
- Authentication: no `allUsers` or `allAuthenticatedUsers` (rejected by variable validation). Invokers are listed explicitly.
- Secrets are referenced from Secret Manager by name and version; no secret values in code, variables or workflows.
- Images must be a commit-SHA tag or a digest (`:latest` is rejected).
- Terraform and provider versions are pinned, and lock files are committed.
- Tests: 5 `terraform test` runs with a mocked provider (default ingress, no invoker bindings, dedicated service account, scoped secret access, rejection of public invokers and of `:latest`).

### State strategy (intended)

- Remote state in a versioned GCS bucket with native locking; the bucket is supplied at `init` time (`-backend-config="bucket=..."`).
- Separate state prefix per environment (`cloudrun/dev`, `cloudrun/prod`); dev and prod ideally live in separate projects.
- Destructive-change review: the plan is saved, rendered in the job summary and uploaded as an artifact. Production applies that exact plan only after environment approval. Any `destroy` or `replace` in the plan needs explicit reviewer acknowledgement. Production uses `deletion_protection = true`.

## Pipelines

**On pull request (`pr-checks.yml`)**: read-only token (`contents: read`). App lint and tests; `terraform fmt`, `validate` and `test`; image build, `/health` smoke test and Trivy gate. Nothing is pushed or deployed.

**After merge to `main` (`release.yml`)**:

1. Build once, tagged with the commit SHA. When pushed, the image digest is recorded and used as the reference for every environment (promote, never rebuild).
2. Evidence (`release.json`: commit, image reference, run ID) is uploaded as an artifact and shown in the job summary.
3. Separate plan jobs (read-only identity) save and upload the plan for dev and prod.
4. Apply jobs use that exact saved plan: dev first, then production behind the `production` environment (required reviewers) and a `prod-deploy` concurrency group, so two production applies cannot run together.
5. Authentication is keyless: GitHub OIDC and Workload Identity Federation (`google-github-actions/auth`), with separate plan, build and apply service accounts and placeholders supplied through repository variables. No service-account keys.
6. All third-party actions are pinned to full commit SHAs, because tags can be moved. The pinning script is `scripts/pin-actions.ps1`; Dependabot or Renovate would keep the pins current.

Cloud steps run only when the repository variable `GCP_ENABLED` is `true`. It is not set, so on this repository only the build job runs and the others show as skipped.

## Rollback

`rollback.yml` is manual, uses the same `production` approval and the same `prod-deploy` lock. It shifts 100% of traffic to a named known-good revision with `gcloud run services update-traffic` and records the traffic before and after. Rolling back the code itself is a revert on `main`, which rebuilds and redeploys through the normal pipeline.

## Cleanup

```
docker stop svc
docker rm svc
docker rmi cloudrun-svc:local
```

No cloud resources were created, so there is nothing to destroy.

## Incident response and HA design

- `docs/incident-response.md`: runbook for a "green pipeline, bad revision" incident.
- `docs/ha-design.md`: two-region Cloud Run behind a global external Application Load Balancer with Cloud Armor (design only).

## Implemented vs conceptual

| Implemented and validated | Conceptual or not run |
|---|---|
| Image build, health check, non-root user, Trivy scan | Real registry push and Cloud Run deployment |
| Terraform module, dev and prod, fmt, validate, 5 tests | `terraform plan` or `apply` against Google Cloud |
| PR workflow (ran green in GitHub Actions) | Workload Identity Federation setup and GitHub environment approvals |
| Release workflow build job (ran on `main`) | Plan, apply, promotion and rollback jobs (skipped, no cloud account) |
| Pinned actions, concurrency and least-privilege permissions in the YAML | Load balancer, Cloud Armor, multi-region failover, RTO and RPO figures |
| Incident runbook and HA design written | Optional kind or minikube resilience extension (not attempted) |

## Time, assumptions, trade-offs, unfinished work

- **Time spent:** about 4 hours in total, including about 1 hour installing local tools (Docker, WSL, Terraform, Trivy) (including installing local tools).
- **Assumptions:** a live Google Cloud deployment is optional, so none was done. The service name `cloudrun-svc` and region `us-central1` are examples.
- **Trade-offs:** mocked-provider tests prove module logic and guardrails, not real Google API behaviour. The 44 unfixed HIGH base-image findings are accepted and documented. The PR job gates Trivy on fixable findings only.
- **Failure encountered:** a PowerShell loop passed `-chdir=terraform\envs\$e` unquoted, so `$e` was never expanded and Terraform reported "cannot find the file specified". Quoting the argument (`"-chdir=terraform\envs\$e"`) fixed it. Earlier, the first `curl` returned "Empty reply from server" because gunicorn had not finished starting; waiting a few seconds fixed it.
- **Unfinished, next steps:** set up a real Google Cloud project with Workload Identity Federation and run plan and apply for dev; add Dependabot for actions and the base image; add canary traffic with automated rollback; add the kind or minikube extension; consider a distroless base image.
- **AI assistance:** I used Claude (Anthropic) throughout to draft the Dockerfile, Terraform module and tests, workflows and documents, and to troubleshoot errors. I ran the commands, checked the outputs, and can explain and change everything in this repository.


