mock_provider "azurerm" {
  override_during = plan
}

variables {
  subscription_id         = "00000000-0000-0000-0000-000000000001"
  operator_ipv4_addresses = ["203.0.113.10"]
}

run "backend_contract" {
  command = plan

  assert {
    condition     = output.backend.resource_group_name == "rg-statusboard-tfstate" && output.backend.container_name == "tfstate" && output.backend.key == "dev.terraform.tfstate"
    error_message = "Bootstrap must retain the development backend coordinates."
  }
}

run "reject_empty_state_allowlist" {
  command = plan

  variables {
    operator_ipv4_addresses = []
  }

  expect_failures = [var.operator_ipv4_addresses]
}
