# keycloak-config

Manages Keycloak identity configuration with the official
`keycloak/keycloak` Terraform provider.

## Why Separate

The Keycloak provider must authenticate against a running Keycloak server.
Therefore, deploy Keycloak first with the `keycloak` module, then run a second
Terraform phase with this module to create realms, groups, clients, and mappers.
For modern Keycloak/Quarkus, keep the base URL as `https://auth.example.com`;
the legacy `/auth` base path is not used.

## Components

- `platform` realm by default
- `platform-admins` and `platform-readonly` groups
- OIDC clients for platform apps
- group membership protocol mapper exposing `groups` in tokens

## Example

```hcl
provider "keycloak" {
  url       = "https://auth.example.com"
  client_id = "admin-cli"
  username  = "admin"
  password  = var.keycloak_admin_password
}

module "keycloak_config" {
  source = "../modules/keycloak-config"

  enabled = true
  oidc_clients = {
    grafana = {
      redirect_uris = ["https://grafana.example.com/login/generic_oauth"]
      web_origins   = ["https://grafana.example.com"]
    }
  }
}
```

Use the output `client_secrets` to configure Grafana, Argo CD, and Kiali.

## References

- [Keycloak Terraform provider](https://registry.terraform.io/providers/keycloak/keycloak/latest)
- [Keycloak OpenID client resource](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client)
