#!/usr/bin/env bash
# Script Purpose: Collect docker compose logs incrementally into centralized files under VOL_KOHA_LOGS.
# Usage: Run on host: ./scripts/collect-docker-logs.sh [--since VALUE] [--dry-run].
set -euo pipefail
umask 027

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT_ARG=""

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

load_env() {
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/autonomous-env.sh"
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/docker-runtime.sh"
  ENVIRONMENT_ARG="$(autonomous_env_arg_from_cli "$@")"
  load_autonomous_env "${PROJECT_ROOT}" "${ENVIRONMENT_ARG}"
  DOCKER_RUNTIME_MODE="${DOCKER_RUNTIME_MODE:-swarm}"
  KOHA_COMPOSE_FILE="${KOHA_COMPOSE_FILE:-$(docker_runtime_detect_compose_file "${PROJECT_ROOT}")}"
  [ -n "${VOL_KOHA_LOGS:-}" ] || die "VOL_KOHA_LOGS is required in env.${AUTONOMOUS_ENVIRONMENT}.enc"
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/collect-docker-logs.sh [options]

Options:
  --since VALUE     Override 'since' window (e.g. 30m, 2h, 2026-03-01T10:00:00Z)
  --env dev|prod    Environment to decrypt (default: SERVER_ENV)
  --dry-run         Do not write files/state, only print summary
  --help            Show help

Environment:
  LOG_EXPORT_ROOT   Output root (default: ${VOL_KOHA_LOGS}/centralized/docker)
  LOG_STATE_FILE    State file (default: ${VOL_KOHA_LOGS}/centralized/.docker_logs_since)
  LOG_FIRST_SINCE   Initial since window if no state exists (default: 24h)
USAGE
}

main() {
  local since_override=""
  local dry_run=false
  local original_args=("$@")

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --since)
        shift
        [ "$#" -gt 0 ] || die "--since requires value"
        since_override="$1"
        ;;
      --dry-run)
        dry_run=true
        ;;
      --env)
        shift
        [ "$#" -gt 0 ] || die "--env requires value"
        ;;
      --env=*)
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
    shift
  done

  load_env "${original_args[@]}"

  local export_root="${LOG_EXPORT_ROOT:-${VOL_KOHA_LOGS}/centralized/docker}"
  local state_file="${LOG_STATE_FILE:-${VOL_KOHA_LOGS}/centralized/.docker_logs_since}"
  local first_since="${LOG_FIRST_SINCE:-24h}"
  local since_value=""

  if [ -n "${since_override}" ]; then
    since_value="${since_override}"
  elif [ -f "${state_file}" ]; then
    since_value="$(tr -d ' \t\r\n' < "${state_file}")"
    [ -n "${since_value}" ] || since_value="${first_since}"
  else
    since_value="${first_since}"
  fi

  mkdir -p "${export_root}" "$(dirname "${state_file}")"

  local now_utc
  now_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local services
  if [[ "$(docker_runtime_mode)" == "swarm" ]]; then
    services="$(docker service ls --filter "label=com.docker.stack.namespace=${STACK_NAME:-koha}" --format '{{.Name}}' | sed "s/^${STACK_NAME:-koha}_//")"
  else
    services="$(docker compose -f "${KOHA_COMPOSE_FILE}" config --services)"
  fi
  [ -n "${services}" ] || die "No docker services found"

  local total_lines=0
  local service
  for service in ${services}; do
    local outfile="${export_root}/${service}.log"
    if ! ${dry_run}; then
      : > /dev/null
      touch "${outfile}"
      chmod 640 "${outfile}"
    fi

    local tmp
    tmp="$(mktemp)"
    if ! docker_runtime_logs "${service}" --no-color --since "${since_value}" >"${tmp}" 2>/dev/null; then
      warn "Failed to collect logs for service: ${service}"
      rm -f "${tmp}"
      continue
    fi

    local line_count
    line_count="$(wc -l < "${tmp}" | tr -d ' ')"
    if [ "${line_count}" -gt 0 ]; then
      total_lines=$((total_lines + line_count))
      if ! ${dry_run}; then
        {
          printf '\n[%s] collect --since=%s --service=%s\n' "${now_utc}" "${since_value}" "${service}"
          cat "${tmp}"
        } >> "${outfile}"
      fi
      log "Collected ${line_count} lines for ${service}"
    else
      log "Collected 0 lines for ${service}"
    fi
    rm -f "${tmp}"
  done

  if ! ${dry_run}; then
    printf '%s\n' "${now_utc}" > "${state_file}"
    log "State updated: ${state_file} -> ${now_utc}"
  fi

  log "Done. Total collected lines: ${total_lines}. Output: ${export_root}"
}

main "$@"
