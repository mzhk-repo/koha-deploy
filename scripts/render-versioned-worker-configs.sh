#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ORCHESTRATOR_ENV_FILE:-}"
WRITE_ENV_FILE=""

declare -a CONFIG_KEYS=()
declare -a CONFIG_NAMES=()

log() { printf '[versioned-worker-configs] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage: scripts/render-versioned-worker-configs.sh --env-file FILE --write-env-file FILE

Creates immutable Docker configs for managed Koha background worker runtime scripts.
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --write-env-file) WRITE_ENV_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "${ENV_FILE}" && -f "${ENV_FILE}" ]] || die 'existing --env-file is required'
[[ -n "${WRITE_ENV_FILE}" && -f "${WRITE_ENV_FILE}" ]] || die 'existing --write-env-file is required'
command -v docker >/dev/null 2>&1 || die 'docker is required'
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required'

register_config() {
  local key="$1" base="$2" path="$3" hash name
  [[ -s "${path}" ]] || die "runtime script is missing or empty: ${path}"
  hash="$(sha256sum "${path}" | awk '{print substr($1, 1, 12)}')"
  name="${base}_${hash}"
  if docker config inspect "${name}" >/dev/null 2>&1; then
    log "Reusing ${name}"
  else
    log "Creating ${name}"
    docker config create --label koha.managed-worker-runtime=true "${name}" "${path}" >/dev/null
  fi
  CONFIG_KEYS+=("${key}")
  CONFIG_NAMES+=("${name}")
}

write_env() {
  local tmp key name index
  for index in "${!CONFIG_KEYS[@]}"; do
    key="${CONFIG_KEYS[${index}]}"
    name="${CONFIG_NAMES[${index}]}"
    tmp="$(mktemp "$(dirname "${WRITE_ENV_FILE}")/.worker-config.XXXXXX")"
    awk -v key="${key}" -v name="${name}" '
      BEGIN { replaced = 0 }
      /^[[:space:]]*#/ { print; next }
      {
        line = $0
        candidate = line
        sub(/^[[:space:]]*export[[:space:]]+/, "", candidate)
        split(candidate, parts, "=")
        if (parts[1] == key) {
          print key "=" name
          replaced = 1
        } else {
          print line
        }
      }
      END { if (!replaced) print key "=" name }
    ' "${WRITE_ENV_FILE}" > "${tmp}"
    mv "${tmp}" "${WRITE_ENV_FILE}"
    chmod 600 "${WRITE_ENV_FILE}"
  done
}

register_config KOHA_WORKER_AUTOSTART_GUARD_CONFIG_NAME koha_worker_autostart_guard "${PROJECT_ROOT}/scripts/container/koha-worker-autostart-guard.sh"
register_config KOHA_BACKGROUND_WORKER_SUPERVISOR_CONFIG_NAME koha_background_worker_supervisor "${PROJECT_ROOT}/scripts/container/koha-background-worker-supervisor.sh"
write_env

for index in "${!CONFIG_KEYS[@]}"; do
  printf '%s=%s\n' "${CONFIG_KEYS[${index}]}" "${CONFIG_NAMES[${index}]}"
done
