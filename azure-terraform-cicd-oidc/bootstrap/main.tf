locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  token_audience  = ["api://AzureADTokenExchange"]
  repo_slug       = "${var.github_owner}/${var.github_repo}"
  container_scope = "${data.azurerm_storage_account.state_storage.id}/blobServices/default/containers/${var.state_container}"

  tags = {
    managed_by = "terraform"
    purpose    = "cicd-oidc"
    owner      = "owner@example.com"
  }
}

data "azurerm_storage_account" "state_storage" {
  name                = var.state_storage_account
  resource_group_name = var.state_resource_group
}

resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "identity" {
  name     = "rg-cicd-identity"
  location = var.location
  tags     = local.tags
}

# ---------- Plan identity (read-only) ----------
resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-tf-plan-github"
  resource_group_name = azurerm_resource_group.identity.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "plan_pr" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = local.token_audience
  issuer                    = local.github_issuer
  subject                   = "repo:${local.repo_slug}:pull_request"
}

resource "azurerm_federated_identity_credential" "plan_main" {
  name                      = "github-main-branch"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = local.token_audience
  issuer                    = local.github_issuer
  subject                   = "repo:${local.repo_slug}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = azurerm_resource_group.target.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
}

resource "azurerm_role_assignment" "plan_state_read" {
  scope                = local.container_scope
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
}

# ---------- Apply identity (write, environment-gated) ----------
resource "azurerm_user_assigned_identity" "apply" {
  name                = "id-tf-apply-github"
  resource_group_name = azurerm_resource_group.identity.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "apply_env" {
  name                      = "github-environment-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.apply.id
  audience                  = local.token_audience
  issuer                    = local.github_issuer
  subject                   = "repo:${local.repo_slug}:environment:${var.github_environment}"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = azurerm_resource_group.target.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
}

resource "azurerm_role_assignment" "apply_state_write" {
  scope                = local.container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
}

# ---------- Optional: Azure DevOps trust on the same identities ----------
resource "azurerm_federated_identity_credential" "plan_ado" {
  count                     = var.ado_issuer != null && var.ado_subject_plan != null ? 1 : 0
  name                      = "azure-devops-plan"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = local.token_audience
  issuer                    = var.ado_issuer
  subject                   = var.ado_subject_plan
}

resource "azurerm_federated_identity_credential" "apply_ado" {
  count                     = var.ado_issuer != null && var.ado_subject_apply != null ? 1 : 0
  name                      = "azure-devops-apply"
  user_assigned_identity_id = azurerm_user_assigned_identity.apply.id
  audience                  = local.token_audience
  issuer                    = var.ado_issuer
  subject                   = var.ado_subject_apply
}