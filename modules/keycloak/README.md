# keycloak

Installs Keycloak as the shared identity provider for platform applications.

## Components

- `keycloak` namespace with optional Istio ambient label
- Kubernetes Secret and ConfigMap for runtime configuration
- MySQL bootstrap Job that creates a dedicated database and user
- Keycloak Deployment and ClusterIP Service
- HTTPRoute for `auth.<domain>` through the shared Gateway
- optional ServiceEntry for the public hostname
- optional ExternalName Service for presenting the database in Kubernetes
- ServiceEntry for the MySQL private DNS name when ambient mesh is enabled

## Database

This module expects an existing MySQL-compatible database. In the Always Free
profile, use the `databases` module with `enable_mysql_heatwave=true` and
`shape_name=MySQL.Free`. The bootstrap Job connects as the MySQL admin user,
creates the `keycloak` database, creates the app user, grants only that schema,
and then Keycloak uses the app credentials.

When the caller provides a private DNS name such as `mysql.platform.internal`,
Keycloak uses that FQDN directly in `KC_DB_URL`. If
`enable_database_external_name_service=true`, the module also creates a
Kubernetes `ExternalName` Service such as `keycloak/mysql` pointing to the same
private DNS name. This presents the database inside the cluster without changing
Keycloak's JDBC path.

For Istio ambient mode, the module creates a mesh-wide ServiceEntry for the
database FQDN, for example:

```yaml
hosts:
  - mysql.platform.internal
ports:
  - number: 3306
    name: mysql
    protocol: TCP
resolution: DNS
```

Avoid pointing Keycloak itself at the Kubernetes `ExternalName` FQDN if the JVM
or mesh DNS path cannot resolve the service consistently during startup. In that
case, keep the `ExternalName` for workloads and use the OCI Private DNS FQDN in
`database_host`.

## Example

```hcl
module "keycloak" {
  source = "../modules/keycloak"

  enabled                   = true
  host                      = "auth.example.com"
  gateway_name              = module.platform.gateway_name
  gateway_namespace         = module.platform.gateway_namespace
  kubeconfig_path           = "~/.kube/config"
  database_host             = module.databases.mysql_private_fqdn
  enable_database_external_name_service = true
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
