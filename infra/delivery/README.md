# Application delivery access

Run this operator-managed root after the development platform exists. It creates delivery identities and scoped role assignments through the [application-delivery module](../modules/application-delivery/README.md). It does not create or configure the cluster, registry or application secret.

Use a separate backend key in the operator-only `bootstrap-state` container. Copy `backend.tfbackend.example` to `backend.tfbackend`, and `terraform.tfvars.example` to `terraform.tfvars`. Fill in the existing platform names, subscription, region and exact repository OIDC subject prefix. All local backend/variable/state/plan files are ignored by Git.

Before applying, create `dev-app-publish` and `dev-app-deploy` GitHub environments. For both, allow only a custom `main` branch policy. Require a trusted reviewer for `dev-app-deploy` and disable administrator bypass. A sole repository owner may review their own manual dispatch.

```sh
terraform -chdir=infra/delivery init -backend-config=backend.tfbackend
terraform -chdir=infra/delivery plan -out=delivery.tfplan
terraform -chdir=infra/delivery show delivery.tfplan
terraform -chdir=infra/delivery apply delivery.tfplan
terraform -chdir=infra/delivery output -json github_secrets
```

Store the output values as `AZURE_APP_PUBLISH_CLIENT_ID`, `AZURE_APP_DEPLOY_CLIENT_ID` and `AZURE_APP_NETWORK_CLIENT_ID` Actions secrets. Reuse the existing tenant and subscription secrets. Allow time for Azure role propagation.

Set repository variables `APP_RESOURCE_GROUP`, `AKS_NAME`, `ACR_NAME` and `ACR_LOGIN_SERVER` to the existing platform values. `ACR_NAME` excludes the `.azurecr.io` suffix. Prepare the [AKS bootstrap resources](../../k8s/README.md#aks-prerequisites) before running application deployment.

This state is independent of both platform and initial bootstrap. For complete decommissioning, review and apply a saved removal plan for delivery access before removing AKS/ACR:

```sh
terraform -chdir=infra/delivery plan -destroy -out=delivery-removal.tfplan
terraform -chdir=infra/delivery show delivery-removal.tfplan
terraform -chdir=infra/delivery apply delivery-removal.tfplan
```

The infrastructure workflow's development destroy operation does not process this root. Destroying the platform first can remove scoped Azure role assignments outside delivery state; refresh and reconcile this root before reusing it. Keep its role definitions/management identities until their removal plan is applied. Backend storage remains a separate bootstrap responsibility.


Monitored AKS writes require Log Analytics linked authorization even when managed identity ingestion and disabled local authentication are configured. Terraform Apply has `Microsoft.OperationalInsights/workspaces/sharedKeys/action` plus explicit ContainerInsights solution lifecycle actions in the workload group. The operator-managed delivery root separately grants the API network identity only `sharedKeys/action` and `Microsoft.OperationsManagement/solutions/write` on the exact Log Analytics workspace when monitoring is enabled. Publisher and application deployment identities receive no workspace grant. This action permits retrieving workspace keys; Terraform does not retrieve or export them, and the workspace rejects key-based authentication. Set `monitoring_enabled = false` in the delivery root when platform monitoring is disabled.
