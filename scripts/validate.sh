#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

roots=(
  "modules/argocd"
  "modules/keycloak"
  "modules/keycloak-config"
  "modules/lab-apps"
  "modules/observability"
  "modules/platform"
  "modules/profiling"
)

for root in "${roots[@]}"; do
  echo "==> terraform validate ${root}"
  terraform -chdir="${root}" init -backend=false >/dev/null
  terraform -chdir="${root}" validate
done
