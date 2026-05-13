#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

mapfile -t roots < <(find modules -mindepth 1 -maxdepth 1 -type d | sort)

for root in "${roots[@]}"; do
  echo "==> tflint ${root}"
  (cd "${root}" && tflint)
done
