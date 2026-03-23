#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  export COMPOSE_FILE="$1"
fi

if [[ -x "./scripts/verify-env.sh" ]]; then
  bash ./scripts/verify-env.sh --example-only
fi

if [[ -x "./scripts/check-secrets-hygiene.sh" ]]; then
  bash ./scripts/check-secrets-hygiene.sh
fi

if [[ -x "./scripts/check-internal-ports-policy.sh" ]]; then
  bash ./scripts/check-internal-ports-policy.sh
fi
