#!/usr/bin/env bash
# Script Purpose: Enforce OIDC lockdown prefs in Koha by disabling OPAC password reset/change preferences.
# Usage: Run on host: ./scripts/koha-lockdown-password-prefs.sh [--apply] [--verify].
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

load_env() {
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/orchestrator-env.sh"
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/docker-runtime.sh"
  ENV_FILE="$(resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}")"
  KOHA_COMPOSE_FILE="$(docker_runtime_detect_compose_file "${PROJECT_ROOT}")"
  DOCKER_RUNTIME_COMPOSE_FILE="${KOHA_COMPOSE_FILE}"
  DOCKER_RUNTIME_ENV_FILE="${ENV_FILE}"
  export KOHA_COMPOSE_FILE DOCKER_RUNTIME_COMPOSE_FILE DOCKER_RUNTIME_ENV_FILE
  load_orchestrator_env_file "${ENV_FILE}"
  [ -n "${KOHA_INSTANCE:-}" ] || die "KOHA_INSTANCE is required"
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/koha-lockdown-password-prefs.sh [--apply] [--verify]

Options:
  --apply    Set OpacResetPassword=0 and OpacPasswordChange=0
  --verify   Verify both preferences are set to 0
  --env-file FILE
             Path to env file (default: ORCHESTRATOR_ENV_FILE, fallback ./.env for dev)
  --help     Show help

Default behavior: --apply and --verify
USAGE
}

apply_changes() {
  log "Applying OIDC lockdown prefs for instance '${KOHA_INSTANCE}'..."
  docker_runtime_exec koha sh -lc "
    koha-mysql '${KOHA_INSTANCE}' -e \"
      UPDATE systempreferences
      SET value='0'
      WHERE variable IN ('OpacResetPassword','OpacPasswordChange');
    \"
  "
}

verify_changes() {
  log "Verifying OpacResetPassword and OpacPasswordChange..."

  local output
  output="$(
    docker_runtime_exec koha sh -lc "
      koha-mysql '${KOHA_INSTANCE}' -N -e \"
        SELECT variable, value
        FROM systempreferences
        WHERE variable IN ('OpacResetPassword','OpacPasswordChange')
        ORDER BY variable;
      \"
    "
  )"

  echo "${output}"

  echo "${output}" | grep -q $'^OpacPasswordChange\t0$' || die "OpacPasswordChange is not 0"
  echo "${output}" | grep -q $'^OpacResetPassword\t0$' || die "OpacResetPassword is not 0"

  log "Verification passed: local password reset/change is disabled in OPAC."
}

main() {
  local do_apply=true
  local do_verify=true
  local flags_seen=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply)
        if ! ${flags_seen}; then
          do_apply=false
          do_verify=false
          flags_seen=true
        fi
        do_apply=true
        ;;
      --verify)
        if ! ${flags_seen}; then
          do_apply=false
          do_verify=false
          flags_seen=true
        fi
        do_verify=true
        ;;
      --env-file)
        shift
        [ "$#" -gt 0 ] || die "--env-file requires value"
        ENV_FILE="$1"
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
    shift
  done

  load_env
  ${do_apply} && apply_changes
  ${do_verify} && verify_changes
}

main "$@"
