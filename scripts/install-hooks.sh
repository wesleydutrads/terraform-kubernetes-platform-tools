#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

if ! command -v pre-commit >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install pre-commit
  else
    echo "pre-commit is required. Install Homebrew first, then run: brew install pre-commit" >&2
    exit 1
  fi
fi

pre-commit install
echo "pre-commit hook installed."
