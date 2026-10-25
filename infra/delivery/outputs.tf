output "github_secrets" {
  description = "Client IDs for the main-only application workflow; store as GitHub Actions secrets."
  value = {
    AZURE_APP_PUBLISH_CLIENT_ID = module.application_delivery.client_ids.publish
    AZURE_APP_DEPLOY_CLIENT_ID  = module.application_delivery.client_ids.deploy
    AZURE_APP_NETWORK_CLIENT_ID = module.application_delivery.client_ids.network
  }
}
