#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
source "${script_dir}/env.sh"

if (( $# > 1 )); then
  printf '%s\n' 'Usage: validate.sh [--init]' >&2
  exit 2
fi

initialize=false
case "${1:-}" in
  "") ;;
  --init) initialize=true ;;
  --help|-h)
    printf '%s\n' 'Usage: validate.sh [--init]' \
      'Default: validate existing initialization; no automatic init or downloads.' \
      '--init: explicitly initialize without backend before validation (may download providers).' \
      'TF_BIN selects an existing Terraform executable (default: terraform).'
    exit 0
    ;;
  *) printf '%s\n' 'Usage: validate.sh [--init]' >&2; exit 2 ;;
esac

tf_bin="${TF_BIN:-terraform}"
if ! command -v "${tf_bin}" >/dev/null 2>&1; then
  printf '%s\n' 'Terraform not found. Set TF_BIN to a verified existing executable; nothing was installed.' >&2
  exit 127
fi
export CHECKPOINT_DISABLE=1 TF_INPUT=0 TF_IN_AUTOMATION=1

roots=()
for module in "${repo_root}"/modules/*; do
  [[ -d "${module}" ]] && roots+=("${module}")
done
if (( ${#roots[@]} == 0 )); then
  printf '%s\n' 'No module directories found.' >&2
  exit 1
fi

for root in "${roots[@]}"; do
  printf '==> terraform validate %s\n' "${root#"${repo_root}/"}"
  if [[ "${initialize}" == true ]]; then
    "${tf_bin}" -chdir="${root}" init -backend=false -input=false >/dev/null
  fi
  if "${tf_bin}" -chdir="${root}" validate; then
    :
  else
    status=$?
    printf '%s\n' 'Validation failed. If dependencies are missing, review initialization separately or explicitly use --init (may download providers).' >&2
    exit "${status}"
  fi
done
