#!/usr/bin/env bash
# Script Purpose: Set Koha REST/API related system preferences from env and flush Koha cache.
# Usage: ./scripts/patch/patch-koha-sysprefs-api.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-sysprefs-api.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --dry-run           Print actions only
  --help              Show help
USAGE
}

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

load_env_file

bool_to_01() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON|enabled|ENABLED|Enabled) printf '1\n' ;;
    0|false|FALSE|False|no|NO|off|OFF|disabled|DISABLED|Disabled) printf '0\n' ;;
    *) die "$2 must be boolean-like (1/0, true/false, yes/no, on/off, enabled/disabled)" ;;
  esac
}

REST_BASIC_AUTH="$(bool_to_01 "${KOHA_REST_BASIC_AUTH:-1}" "KOHA_REST_BASIC_AUTH")"

log "Patching systempreferences: RESTBasicAuth=${REST_BASIC_AUTH}"

if ${DRY_RUN}; then
  log "DRY-RUN: skip DB update and Koha cache flush"
  exit 0
fi

SQL="
UPDATE systempreferences SET value='${REST_BASIC_AUTH}' WHERE variable='RESTBasicAuth';
SELECT variable, value FROM systempreferences
WHERE variable IN ('RESTBasicAuth')
ORDER BY variable;
"

docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE:-library}" -e "${SQL}"

log "Flushing Koha cache after REST/API sysprefs update"
docker_runtime_exec koha koha-shell "${KOHA_INSTANCE:-library}" -c \
  'perl -MKoha::Caches -e "Koha::Caches->get_instance->flush_all; print qq(cache flush ok\n)"'

log "Done: REST/API system preferences"
