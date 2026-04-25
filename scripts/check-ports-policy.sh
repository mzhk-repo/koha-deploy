#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  COMPOSE_FILE="$1"
elif [[ -n "${COMPOSE_FILE:-}" ]]; then
  COMPOSE_FILE="${COMPOSE_FILE}"
elif [[ -f "docker-compose.yaml" ]]; then
  COMPOSE_FILE="docker-compose.yaml"
elif [[ -f "docker-compose.yml" ]]; then
  COMPOSE_FILE="docker-compose.yml"
else
  echo "ERROR: compose file not found (expected docker-compose.yaml|yml)" >&2
  exit 1
fi

export COMPOSE_FILE

if [[ -x "./scripts/verify-env.sh" ]]; then
  bash ./scripts/verify-env.sh --example-only
fi

if [[ -x "./scripts/check-internal-ports-policy.sh" ]]; then
  bash ./scripts/check-internal-ports-policy.sh
fi
