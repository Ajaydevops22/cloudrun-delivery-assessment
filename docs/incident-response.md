# Incident response: elevated latency and intermittent errors after a "green" deploy

Scenario: the pipeline reported success, but the new Cloud Run revision shows high latency and intermittent 5xx errors right after rollout.

Status: this is a written runbook. It was not exercised against a live environment (no GCP account used for this assessment). The rollback path it relies on is implemented in `.github/workflows/rollback.yml`.

## 1. First 10-15 minutes: evidence to gather

Goal: decide quickly whether this release caused it, and restore service if so.

| Minute | Action | Where |
|---|---|---|
| 0-2 | Confirm impact: error rate, p95/p99 latency, request count vs. baseline. Note start time. | Cloud Monitoring (`run.googleapis.com/request_latencies`, `request_count` by `response_code_class`) |
| 0-2 | Match the start time to the release: commit SHA, image digest, run ID. | `release-evidence` artifact (`release.json`), Actions run summary |
| 2-5 | Compare revisions: traffic split, image digest, env vars, CPU/memory, concurrency, min/max instances. | `gcloud run revisions list` and `gcloud run revisions describe <rev>` |
| 2-5 | Errors by revision: are failures only on the new revision? | Logs filtered by `resource.labels.revision_name` |
| 5-10 | Instance behaviour: instance count, CPU and memory utilisation, cold starts, restarts, OOM kills, startup probe failures. | Cloud Monitoring (`container/instance_count`, `container/cpu/utilizations`, `container/memory/utilizations`), logs |
| 5-10 | Dependencies: latency and errors to downstream services, secret access, DNS or egress failures. | Application logs, dependency dashboards, Cloud Audit Logs |
| 10-15 | Platform status and recent changes: Google Cloud status page, any Terraform apply or IAM change in the same window. | Status page, Audit Logs, Terraform plan artifact |

Useful commands:

## 2. Separating the hypotheses

| Hypothesis | Evidence for it | Evidence against it | Quick test |
|---|---|---|---|
| Application (code regression) | Errors and latency only on the new revision; stack traces; same inputs fine on old revision | Old and new revisions fail equally | Send the same request to the previous revision (tagged URL) |
| Configuration | Revision diff shows changed env vars, memory, CPU, concurrency, timeout | Revision settings identical to the previous one | `describe` both revisions and diff them |
| Identity and secrets | 403 or permission-denied logs, secret access failures, token errors | No permission errors in Cloud Audit Logs | Check audit logs for the runtime service account |
| Networking | Timeouts or connection resets to downstreams, DNS errors, ingress or LB 502/503 | Latency is inside the container, not at the edge | Compare LB or edge latency with container latency |
| Scaling | Instance count pinned at max, queueing, many cold starts, CPU at 100% | Instance count and utilisation have headroom | Check instance count against `max_instances` and concurrency |
| Downstream dependency | Failures correlate with dependency latency or errors, also visible on old revision | Dependency healthy and old revision unaffected | Check dependency dashboards, run a synthetic call |

Rule of thumb: if only the new revision is unhealthy, suspect application or configuration. If both revisions are unhealthy, suspect a dependency, platform, or a shared identity or network change.

## 3. Owners and what each needs

| Owner | Needs from the responder |
|---|---|
| Application team | Failing endpoints, error samples and stack traces, revision name, commit SHA, start time |
| Platform / SRE (on-call) | Impact summary, timeline, traffic split, rollback decision, Terraform run link |
| Security / IAM | Service account name, denied permissions, audit log entries |
| Network team | Request path, timeout and error samples, source and destination, LB or ingress settings |
| Dependency owner | Dependency name, error and latency samples, start time, request volume |
| Incident commander / stakeholders | Customer impact, current status, next update time |

## 4. Decision triggers

| Condition | Action |
|---|---|
| 5xx rate above 2% or p95 latency above 2x baseline for 5 minutes, and only on the new revision | Roll back immediately: send 100% of traffic to the last known-good revision (`rollback.yml`) |
| Impact is partial and the cause is unclear, canary traffic is in use | Shift traffic back in steps (for example 50%, then 10%, then 0%) and watch metrics |
| Both old and new revisions are affected | Do not roll back (it will not help). Continue investigating dependency, platform, and shared config |
| Impact is small and stable, rollback is risky (for example a schema change) | Keep investigating with a time limit, prepare a forward fix, and agree a deadline for rollback |

Rollback is the default when the new revision is clearly the problem, because it restores service fastest. Diagnosis continues after recovery.

## 5. Preserve evidence while restoring service

- Do not delete the failing revision. Keep it with 0% traffic (optionally tagged, for example `failed-<sha>`) so it can still be inspected.
- Save `gcloud run revisions describe` output for the good and bad revisions.
- Export logs and metrics for the incident window (start time to recovery) to a bucket or attach to the incident ticket.
- Keep the release evidence: commit SHA, image digest, `release.json`, and the reviewed Terraform plan artifact for that release.
- Record a timeline: detection time, decisions, who approved the rollback, recovery time.
- Run a blameless review within a few days with action items.

## 6. One improvement to reduce recurrence

Progressive delivery with automatic rollback. Deploy the new revision with 0% traffic and a tag, run smoke tests against the tagged URL, shift 10% of traffic, wait while an alert policy checks the per-revision error rate and p95 latency against the SLO, and continue (to 50%, then 100%) only if healthy. If the alert fires, shift traffic back automatically. This catches problems that a "green" pipeline cannot see, such as latency regressions under real traffic.
