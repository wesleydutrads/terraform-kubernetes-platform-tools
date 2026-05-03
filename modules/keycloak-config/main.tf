resource "keycloak_realm" "this" {
  count = var.enabled ? 1 : 0

  realm   = var.realm_name
  enabled = true
}

resource "keycloak_group" "admin" {
  count = var.enabled ? 1 : 0

  realm_id = keycloak_realm.this[0].id
  name     = var.admin_group
}

resource "keycloak_group" "readonly" {
  count = var.enabled ? 1 : 0

  realm_id = keycloak_realm.this[0].id
  name     = var.readonly_group
}

resource "keycloak_openid_client" "this" {
  for_each = var.enabled ? var.oidc_clients : {}

  realm_id  = keycloak_realm.this[0].id
  client_id = each.key
  name      = each.key
  enabled   = true

  access_type                  = try(each.value.public_client, false) ? "PUBLIC" : "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  valid_redirect_uris          = each.value.redirect_uris
  web_origins                  = each.value.web_origins
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  for_each = var.enabled ? var.oidc_clients : {}

  realm_id  = keycloak_realm.this[0].id
  client_id = keycloak_openid_client.this[each.key].id
  name      = "groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

locals {
  platform_group_ids = var.enabled ? {
    (var.admin_group)    = keycloak_group.admin[0].id
    (var.readonly_group) = keycloak_group.readonly[0].id
  } : {}
}

resource "keycloak_user" "platform" {
  for_each = var.enabled ? var.users : {}

  realm_id       = keycloak_realm.this[0].id
  username       = each.key
  enabled        = try(each.value.enabled, true)
  email          = try(each.value.email, null)
  first_name     = try(each.value.first_name, null)
  last_name      = try(each.value.last_name, null)
  email_verified = try(each.value.email_verified, true)

  initial_password {
    value     = each.value.initial_password
    temporary = try(each.value.temporary_password, true)
  }
}

resource "keycloak_user_groups" "platform" {
  for_each = var.enabled ? var.users : {}

  realm_id = keycloak_realm.this[0].id
  user_id  = keycloak_user.platform[each.key].id
  group_ids = [
    for group_name in try(each.value.groups, []) : local.platform_group_ids[group_name]
  ]
}

data "keycloak_role" "master_realm_admin" {
  count = var.enabled && var.master_admin_user != null ? 1 : 0

  realm_id = "master"
  name     = "admin"
}

resource "keycloak_user" "master_admin" {
  count = var.enabled && var.master_admin_user != null ? 1 : 0

  realm_id       = "master"
  username       = var.master_admin_user.username
  enabled        = try(var.master_admin_user.enabled, true)
  email          = try(var.master_admin_user.email, null)
  first_name     = try(var.master_admin_user.first_name, null)
  last_name      = try(var.master_admin_user.last_name, null)
  email_verified = try(var.master_admin_user.email_verified, true)

  initial_password {
    value     = var.master_admin_user.initial_password
    temporary = try(var.master_admin_user.temporary_password, true)
  }
}

resource "keycloak_user_roles" "master_admin" {
  count = var.enabled && var.master_admin_user != null ? 1 : 0

  realm_id = "master"
  user_id  = keycloak_user.master_admin[0].id
  role_ids = [data.keycloak_role.master_realm_admin[0].id]
}
