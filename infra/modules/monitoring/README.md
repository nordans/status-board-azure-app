# monitoring

Creates Azure Monitor and Log Analytics workspaces, a metrics endpoint, collection rules and AKS associations, control-plane diagnostic settings and Prometheus alert groups. The development root connects the Log Analytics output to the AKS agent.

Log Analytics is managed through AzAPI with local authentication disabled. Terraform does not request or export workspace shared keys. Azure requires the caller to hold `sharedKeys/action` for AKS/DCR linked authorization even when ingestion uses managed identity. The module inherits AzureRM/AzAPI authentication, shares the development state and requires the existing workload resource group.

Application alerts load the repository's `observability/rules.json`. Node and Deployment alerts use managed Kubernetes metrics. Alerts have no external notification actions by default. See [monitoring operations](../../../observability/README.md) for rollout, access, verification, cost controls and removal.
