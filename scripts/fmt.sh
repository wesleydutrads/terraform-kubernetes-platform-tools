#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

terraform fmt -check -recursive
