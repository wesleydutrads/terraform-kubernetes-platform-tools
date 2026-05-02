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
