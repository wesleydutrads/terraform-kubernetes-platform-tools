# keycloak

Installs Keycloak as the shared identity provider for platform applications.

## Components

- `keycloak` namespace with optional Istio ambient label
- Kubernetes Secret and ConfigMap for runtime configuration
- MySQL bootstrap Job that creates a dedicated database and user
- Keycloak Deployment and ClusterIP Service
- HTTPRoute for `auth.<domain>` through the shared Gateway
- optional ServiceEntry for the public hostname

## Database

This module expects an existing MySQL-compatible database. In the Always Free
profile, use the `databases` module with `enable_mysql_heatwave=true` and
`shape_name=MySQL.Free`. The bootstrap Job connects as the MySQL admin user,
creates the `keycloak` database, creates the app user, grants only that schema,
and then Keycloak uses the app credentials.

## Example

```hcl
module "keycloak" {
  source = "../modules/keycloak"

  enabled                   = true
  host                      = "auth.example.com"
  gateway_name              = module.platform.gateway_name
  gateway_namespace         = module.platform.gateway_namespace
  kubeconfig_path           = "~/.kube/config"
  database_host             = module.databases.mysql_endpoint.host
  database_admin_username   = module.databases.mysql_admin_username
  database_admin_password   = module.databases.mysql_admin_password
}
```

## OIDC

Use the `keycloak-config` module with the official `keycloak/keycloak` provider
to manage realms, groups, clients, and protocol mappers after Keycloak is
running. This keeps deployment and identity configuration in separate Terraform
phases and avoids provider bootstrap cycles.

## References

- [Keycloak database configuration](https://www.keycloak.org/server/db)
- [Keycloak container configuration](https://www.keycloak.org/server/containers)
