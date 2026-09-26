mock_provider "azurerm" {}

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  purpose             = "workload"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  location            = "eastus2"
  tags                = { environment = "lab" }
}

run "no_federated_credential_without_an_issuer" {
  command = plan

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 0
    error_message = "the credential cannot be declared before the cluster publishes its issuer"
  }
}

run "partial_federation_inputs_never_produce_a_credential" {
  command = plan

  # Testing only the two extremes -- nothing supplied, everything supplied --
  # leaves the conditional itself unguarded. If its `&&` ever became `||`, a
  # single populated variable would mint a credential whose subject reads
  # "system:serviceaccount::workload": syntactically fine, never matches, and
  # the symptom looks like a permissions problem rather than a typo.
  variables {
    oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/00000000/11111111/"
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 0
    error_message = "an issuer without a service account must never produce a credential with a malformed subject"
  }
}

run "a_service_account_without_an_issuer_produces_no_credential" {
  command = plan

  variables {
    service_account_namespace = "apps"
    service_account_name      = "workload"
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 0
    error_message = "a service account without an issuer must never produce a credential"
  }
}

run "federated_credential_uses_the_token_exchange_audience" {
  command = plan

  variables {
    oidc_issuer_url           = "https://eastus2.oic.prod-aks.azure.com/00000000/11111111/"
    service_account_name      = "workload"
    service_account_namespace = "apps"
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 1
    error_message = "supplying an issuer must produce exactly one federated credential"
  }

  assert {
    condition     = one(values(azurerm_federated_identity_credential.this)).audience == tolist(["api://AzureADTokenExchange"])
    error_message = "the audience is fixed by Azure; any other value silently fails to exchange"
  }

  assert {
    condition     = one(values(azurerm_federated_identity_credential.this)).subject == "system:serviceaccount:apps:workload"
    error_message = "the subject must name the Kubernetes service account in the system:serviceaccount:namespace:name form"
  }
}
