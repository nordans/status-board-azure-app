# Monitoring operations

The application exports Prometheus metrics at `/metrics`. Local monitoring uses Prometheus, Grafana and Alertmanager. AKS uses Azure Monitor managed Prometheus and Container Insights. Application rules in `rules.json` are shared by local Prometheus and Terraform. Kubernetes availability rules run only in Azure.

## Local stack

Run from the repository root with Docker Desktop running:

```sh
uv run python scripts/new_local_secret.py
docker compose -p status-board-observability -f compose.yaml -f compose.monitoring.yaml up --build --detach --wait
uv run python scripts/verify_observability.py
```

| Service | URL |
| --- | --- |
| Application | http://localhost:8000 |
| Grafana | http://localhost:3000/d/status-board |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |

All published ports bind to `127.0.0.1`. Grafana provides anonymous Viewer access, a provisioned datasource and a read-only dashboard. No administrator account is created. Do not publish these workstation ports on a server.

Prometheus retains up to 24 hours of samples with a 1 GB TSDB retention target. Named volumes preserve data across container recreation. Alertmanager groups alerts and exposes their state in its UI; its receiver has no email, webhook or paging integration. Azure alerts also have no external notification action. Configure and test a receiver/action group before relying on unattended notification.

Exercise an outage and recovery:

```sh
uv run python scripts/verify_observability.py --exercise-outage
```

This stops only `status-board` in the named Compose project, waits for `StatusBoardDown`, checks receipt by Alertmanager, restores the service in a `finally` block and checks resolution. Allow approximately four minutes. Application reports are in memory and are lost when the process stops. The test expects the default localhost ports.

Stop the stack, retaining volumes:

```sh
docker compose -p status-board-observability -f compose.yaml -f compose.monitoring.yaml down
```

Add `--volumes` only when local monitoring history is no longer needed.

### Image vulnerability status

Prometheus 3.x and Alertmanager 0.34.1 use immutable official image digests. The local Grafana image uses the pinned 13.2.4 distroless-slim base and copies only its Prometheus datasource from the pinned full release. The 2026-10-26 Trivy scan with the application policy (`HIGH,CRITICAL`, fixed-version findings) reported no findings for Prometheus, eleven HIGH occurrences across nine CVEs for the built Grafana image and twelve HIGH occurrences across five CVEs for Alertmanager. No CRITICAL findings were reported. These local artifacts do not pass a zero-HIGH vulnerability gate. No scan exclusions were added. Check for patched stable artifacts before broader use; neither Grafana nor Alertmanager is deployed to Azure by this module.

Recheck a pinned image with the repository's Trivy version:

```powershell
New-Item -ItemType Directory -Force .cache | Out-Null
docker image save --output .cache/grafana-scan.tar status-board-grafana:local
docker run --rm --volume "${PWD}/.cache:/scan:ro" aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c image --input /scan/grafana-scan.tar --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1
```

## Metrics and alerts

| Metric | Labels | Purpose |
| --- | --- | --- |
| `status_board_http_requests_total` | method, route, status | Request counts and server error ratio |
| `status_board_http_request_duration_seconds` | method, route | Duration histogram for p95 queries |
| `status_board_ready` | none | Token readiness at scrape time |

Routes use templates such as `/api/services/{service_id}/status`. Unknown paths share `unmatched`; unknown HTTP methods share `OTHER`. Labels exclude query strings, report messages, tokens and service ID values. Metrics scrapes do not increment request counters. Each application instance owns a registry; counters reset on restart. This follows the existing single-process deployment model.

The dashboard measures requests handled by Status Board. `response_time_ms` in a service report is separate client-provided data. Health traffic is excluded from dashboard traffic/latency queries and application error/latency alerts.

| Application alert | Condition | Pending period |
| --- | --- | --- |
| StatusBoardDown | Target unavailable or missing | 2 minutes |
| StatusBoardNotReady | Token readiness gauge is zero | 2 minutes |
| StatusBoardHighErrorRate | HTTP 5xx above 5%, at least 20 requests in 5 minutes | 5 minutes |
| StatusBoardHighLatency | p95 above 500 ms, at least 20 requests in 5 minutes | 5 minutes |

CI runs `rule-tests.json` with the pinned Prometheus `promtool` image and validates both service configurations. Tests cover outage/recovery, missing targets, readiness, sustained errors, low traffic and slow/fast requests. The full container outage exercise is an operator test.

## Azure rollout

The development root enables `monitoring_enabled` by default. Setting it to `false` omits the module and both AKS agents. Monitoring shares the platform state and is included in the same saved deployment/removal plans.

The module creates Log Analytics and Azure Monitor workspaces, a metrics endpoint, metrics/log collection rules and cluster associations, control-plane diagnostic settings, and two Prometheus alert groups. AKS uses managed identity authentication for logs. No separate Azure Managed Grafana is provisioned.

Log Analytics has 30-day retention, a 1 GB daily ingestion quota and disabled local/shared-key authentication. The quota is an ingestion guardrail, not a billing ceiling: enforcement can overshoot and stops log availability. Prometheus ingestion has separate charges. Workspace endpoints use public Azure networking with Entra authorization; Private Link is not configured.

Selected streams are ContainerLogV2, Kubernetes events and pod inventory. Inventory uses namespace inclusion. ContainerLogV2 has its own ingestion transformation for `status-board`, `status-board-ingress` and `cert-manager`; inventory filters alone do not filter container logs. The agent ConfigMap excludes system container logs and environment-variable collection. API server, controller-manager and scheduler resource logs use dedicated tables. Full Container Insights performance tables and audit logs are not enabled.

Before deployment:

1. An authorized subscription operator registers `Microsoft.Monitor`, `Microsoft.OperationalInsights`, `Microsoft.Insights` and `Microsoft.AlertsManagement` if needed. Provider auto-registration remains disabled.
2. Plan the bootstrap root and review its platform-deploy custom role update. Apply that saved plan as the bootstrap operator before running the infrastructure workflow. It grants explicit monitoring resource read/write/delete actions in the existing workload resource group. Azure also requires `Microsoft.OperationalInsights/workspaces/sharedKeys/action` for linked authorization when creating the monitored AKS resource and log collection rule, even with managed identity ingestion. The Apply role includes this action in the workload resource group; it can retrieve workspace keys, although local/key authentication remains disabled. No wildcard actions, log-query permission or additional role delegation is added.
3. Resolve soft-deleted Key Vault name recovery from the previous teardown. Use the existing main-only workflow to review and apply a fresh platform plan. Monitoring is part of this same platform apply.
4. Bootstrap application identities, token, CSI and public Gateway using the Kubernetes runbooks. Apply monitoring ConfigMaps with the operator's explicit kubeconfig/context:

```sh
kubectl --kubeconfig <operator-kubeconfig> --context status-board-azure apply -k k8s/bootstrap/monitoring
```

The managed metrics replica scrapes the internal application Service every 30 seconds; unrestricted annotation scraping is not enabled. Public HTTPS permits application/API/health/static paths and `/openapi.json`, with no route for `/metrics`. The public deployment probe requires 404 for `/metrics` and `/metrics/`.

The `kube-system` ConfigMaps are operator-owned. Application deployment credentials retain their namespace boundary. Deploy the application with the existing workflow, then check collection. Allow up to 15 minutes for initial ingestion. Using an operator account with workspace query rights, run this PowerShell example:

```powershell
$telemetry = (terraform -chdir=infra/environments/dev output -json monitoring | ConvertFrom-Json)
uv run python scripts/verify_azure_monitoring.py `
  --query-endpoint $telemetry.prometheus_query_endpoint `
  --workspace-resource-id $telemetry.log_analytics_workspace_id `
  --expected-version (git rev-parse origin/main)
```

The script requires fresh application/readiness and Kubernetes node metrics plus an application-start log for the expected commit. It obtains Entra tokens through Azure CLI without printing them or putting them in process arguments. A successful Terraform apply alone does not prove ingestion.

Example Log Analytics query:

```kusto
ContainerLogV2
| where TimeGenerated > ago(30m) and PodNamespace == "status-board"
| extend event = parse_json(LogMessage)
| where tostring(event.event) == "http_request"
| project TimeGenerated, Route=tostring(event.route), Status=toint(event.status), DurationMs=todouble(event.duration_ms)
| order by TimeGenerated desc
```

Azure platform alerts cover a node remaining NotReady for five minutes and the application Deployment having no available replica for two minutes. Bootstrap, maintenance and teardown can trigger availability alerts. Internal scraping does not prove public DNS/TLS availability; the external deployment probe checks HTTPS at deployment time, not continuously.

## Teardown

Delete monitoring ConfigMaps with the same explicit kubeconfig/context before cluster removal:

```sh
kubectl --kubeconfig <operator-kubeconfig> --context status-board-azure delete -k k8s/bootstrap/monitoring --ignore-not-found
```

Follow the existing public ingress, delivery-access and platform teardown order. Use the saved `plan -destroy` and apply that exact file. Monitoring is in platform state; preserve the bootstrap backend. Verify workload and node resource groups, and separately check any Azure Monitor-managed group and soft-deleted Log Analytics workspace. Retained data follows Azure retention behavior. Run a fresh second removal plan to confirm convergence.

## References

- [AKS monitoring onboarding](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable)
- [Microsoft managed Prometheus Terraform template](https://github.com/Azure/prometheus-collector/tree/main/AddonTerraformTemplate)
- [Custom managed Prometheus scrape jobs](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-scrape-configmap)
- [Container Insights transformations](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-transformations)
