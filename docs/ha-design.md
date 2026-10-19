# HA and load-balancing design (two-region Cloud Run)

Status: **design only**. Nothing in this document was deployed. What exists in the repository is listed in section 9.

## 1. Target architecture
             Clients
                |
      Global anycast IP + DNS
                |
  Global external Application Load Balancer
     (TLS, Cloud Armor security policy)
                |
          Backend service
      /                      \

- Two identical Cloud Run services (same module, same image digest), one per region, for example `us-central1` and `us-east1`.
- A global external Application Load Balancer fronts both through serverless NEGs. Clients use one anycast IP.
- Cloud Armor is attached to the backend service: preconfigured WAF rules, rate limiting, IP deny lists. New rules start in preview mode.
- Cloud Run ingress stays `internal and cloud load balancing`, so the `run.app` URLs are not reachable directly. This is already the default in `terraform/modules/cloud_run`.

## 2. Traffic routing

The load balancer sends each request to the closest healthy region (proximity based). Both regions serve traffic at the same time (active-active). Autoscaling in each region absorbs the load shifted from the other, so `max_instances` and project quotas must be sized for one region carrying 100% of traffic.

## 3. Regional failure detection, failover, recovery, failback

| Phase | Mechanism | Notes |
|---|---|---|
| Detection | Serverless NEGs do not support standard load balancer health checks. Use outlier detection on the backend service (eject a backend that returns many 5xx), plus external uptime checks and alerts on per-region error rate. | To be confirmed against current Google documentation before relying on it. |
| Failover | Automatic ejection of the failing region by outlier detection. Manual lever: set the failing NEG's capacity scaler to 0 (one Terraform change or one `gcloud` command). | Manual path is the tested fallback. |
| Recovery | Region is repaired or Google restores it. Redeploy the same image digest if needed. | Verify with a tagged-revision smoke test. |
| Failback | Return traffic gradually: scaler 0, then partial capacity, then full, while watching error rate and latency. | Avoids a thundering herd on a cold region. |

## 4. Dependencies that can stop the service being truly highly available

Cloud Run is stateless, so the service itself can run in two regions. These parts decide real availability:

- **Database or other stateful store:** a single-region Cloud SQL instance is a single point of failure. Options: regional HA plus a cross-region replica (promotion takes minutes and may lose recent writes), or a multi-region store such as Spanner or Firestore multi-region.
- **Cache (for example Memorystore):** regional. Needs a per-region cache or a design that tolerates cache loss.
- **Object storage:** use a multi-region or dual-region bucket.
- **Messaging:** Pub/Sub is global, but subscribers and ordering rules still matter.
- **Third-party and downstream APIs:** only as available as their own region and rate limits.
- **Container registry:** use a multi-region Artifact Registry repository, or replicate images, so a new region can pull the image during an incident.
- **Secrets:** Secret Manager supports replication across regions. Use automatic or multi-region replication for production secrets.
- **Shared control points:** the load balancer, DNS, Cloud Armor and IAM are global control planes. Terraform state bucket and GitHub Actions are needed to change anything during an incident.

## 5. RTO and RPO (assumptions, not measured)

| Metric | Assumption | Reason |
|---|---|---|
| RPO, service tier | 0 | Stateless, no local data. |
| RPO, data tier | Depends on the store: 0 for multi-region synchronous stores, minutes for cross-region replicas | Not part of this repository. |
| RTO, automatic failover | About 5 minutes | Outlier detection ejects the failing backend and traffic moves. |
| RTO, manual failover | About 15 minutes | Alert, human decision, scaler change. |

What would validate these numbers:

1. Game day: deploy a deliberately failing revision (or deny the invoker role) in one region and record time from first failure to the first successful request served by the other region.
2. Load test during the drill to confirm the surviving region scales to 100% of traffic without hitting quotas.
3. Failback drill with the same measurements.
4. A data-tier restore or promotion test measuring real RPO and RTO for the chosen database.

## 6. Identity and secrets

- One dedicated runtime service account per service and environment, with only `secretmanager.secretAccessor` on the secrets it references (implemented in the module).
- Authentication decision: public APIs behind the load balancer need either end-user authentication in the application or Identity-Aware Proxy. Opening `roles/run.invoker` to everyone is blocked in the module on purpose. If a public endpoint is required, that would be a separate, reviewed change that also keeps ingress locked to the load balancer and Cloud Armor in front.
- Secrets are referenced by name and version, never stored in code, workflow files, Terraform variables or state.
- CI/CD uses GitHub OIDC with Workload Identity Federation and separate plan and apply identities, no long-lived keys.

## 7. Observability, rollback, cost

**Observability**
- Load balancer request logs and metrics split by backend (region).
- Cloud Run metrics per revision: latency, 5xx rate, instance count, CPU and memory.
- Uptime checks from several locations and SLO-based alerts on error rate and latency per region.

**Rollback**
- Roll out one region first (canary region), then the second.
- Per-region traffic can return to a known-good revision (`rollback.yml` implements the traffic shift for one service).
- Keep the previous revision and image digest available.

**Cost (list prices from Google pricing pages, checked October 2026; verify before use)**
- Load balancer forwarding rule: about $0.025 per hour (roughly $18 per month) plus data processing per GB.
- Cloud Armor Standard: $5 per policy per month, $1 per rule per month, $0.75 per million requests.
- Second region: nearly free when `min_instances = 0`; each always-on instance adds compute cost. Production keeps one warm instance per region to avoid cold-start latency.
- Cross-region database replicas and egress are usually the largest cost.

## 8. Trade-offs

- Active-active gives faster failover than active-passive but needs both regions sized for full load and a data tier that supports it.
- Without a multi-region data store the system is only "highly available for stateless requests". Stating this clearly matters more than drawing two boxes.

## 9. Implemented versus conceptual

| Item | State |
|---|---|
| Cloud Run Terraform module with ingress default `internal and cloud load balancing`, no public invoker, dedicated service account | Implemented and tested (`terraform test`, 5 passing) |
| Region is a variable, so a second region is another module instance | Implemented (variable only, not deployed) |
| Release workflow and rollback workflow (traffic shift) | Implemented, GCP steps skipped (no cloud account) |
| Load balancer, serverless NEGs, Cloud Armor policy | Conceptual |
| Outlier detection or other failover tuning | Conceptual, needs validation |
| Multi-region data tier | Conceptual |
| RTO and RPO figures | Assumptions, not measured |
