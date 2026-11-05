# Exemplo inerte: não instala recursos nem seleciona horizonte de retenção.
module "profiling" {
  source = "../../modules/profiling"

  enabled           = false
  gateway_name      = "shared"
  gateway_namespace = "gateway-system"
  host              = "profiles.example.invalid"

  compactor_blocks_retention_period_seconds = null
}
