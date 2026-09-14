#!/usr/bin/env bash
# Fail closed before post-deploy patches unless Koha has an initialized schema.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-}"

log() { printf '[koha-db-schema-guard] %s\n' "$*"; }
die() { printf '[koha-db-schema-guard] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./scripts/koha-db-schema-guard.sh [--env-file FILE]

Verify that systempreferences.Version exists and is non-empty before any
post-deploy database patching. An empty database must be initialized through
the Koha Web installer or restored from backup, then deployed again.
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      shift
      [[ "$#" -gt 0 ]] || die "--env-file requires value"
      ENV_FILE="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

# shellcheck source=scripts/lib/orchestrator-env.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/orchestrator-env.sh"
# shellcheck source=scripts/lib/docker-runtime.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-runtime.sh"
trap orchestrator_env_cleanup EXIT

resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}" ENV_FILE
KOHA_COMPOSE_FILE="$(docker_runtime_detect_compose_file "${PROJECT_ROOT}")"
DOCKER_RUNTIME_COMPOSE_FILE="${KOHA_COMPOSE_FILE}"
DOCKER_RUNTIME_ENV_FILE="${ENV_FILE}"
export KOHA_COMPOSE_FILE DOCKER_RUNTIME_COMPOSE_FILE DOCKER_RUNTIME_ENV_FILE
load_orchestrator_env_file "${ENV_FILE}"
[[ -n "${KOHA_INSTANCE:-}" ]] || die "KOHA_INSTANCE is required"

if ! version="$({
  docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE}" -N -B -e \
    "SELECT COALESCE(NULLIF(TRIM(value), ''), '') FROM systempreferences WHERE variable='Version' LIMIT 1;"
} 2>&1)"; then
  die "cannot verify Koha schema: ${version}"
fi

version="$(printf '%s\n' "${version}" | tr -d '\r' | tail -n 1)"
[[ -n "${version}" ]] || die "systempreferences.Version is missing or empty; use the Web installer or restore, then rerun deploy"

log "Koha schema verified (Version=${version})"
