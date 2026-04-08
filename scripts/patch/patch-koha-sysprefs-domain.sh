#!/usr/bin/env bash
# Script Purpose: Set Koha domain system preferences (OPACBaseURL, staffClientBaseURL) from .env.
# Usage: ./scripts/patch/patch-koha-sysprefs-domain.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-sysprefs-domain.sh [options]

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

normalize_url() {
  local url="$1"
  [ -n "${url}" ] || return 1

  case "${url}" in
    http://*|https://*) ;;
    *) url="https://${url}" ;;
  esac

  case "${url}" in
    */) ;;
    *) url="${url}/" ;;
  esac

  printf '%s' "${url}"
}

sql_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\'/\'\'}"
  printf '%s' "${v}"
}

OPAC_URL_RAW="${OPACBaseURL:-}"
STAFF_URL_RAW="${staffClientBaseURL:-}"

if [ -z "${OPAC_URL_RAW}" ]; then
  OPAC_HOST="${KOHA_OPAC_SERVERNAME:-}"
  [ -n "${OPAC_HOST}" ] || die "Set OPACBaseURL or KOHA_OPAC_SERVERNAME in ${ENV_FILE}"
  OPAC_URL_RAW="${OPAC_HOST}"
fi

if [ -z "${STAFF_URL_RAW}" ]; then
  STAFF_HOST="${KOHA_INTRANET_SERVERNAME:-}"
  [ -n "${STAFF_HOST}" ] || die "Set staffClientBaseURL or KOHA_INTRANET_SERVERNAME in ${ENV_FILE}"
  STAFF_URL_RAW="${STAFF_HOST}"
fi

OPAC_URL="$(normalize_url "${OPAC_URL_RAW}")"
STAFF_URL="$(normalize_url "${STAFF_URL_RAW}")"
OPAC_URL_SQL="$(sql_escape "${OPAC_URL}")"
STAFF_URL_SQL="$(sql_escape "${STAFF_URL}")"

log "Patching systempreferences: OPACBaseURL=${OPAC_URL}, staffClientBaseURL=${STAFF_URL}"

if ${DRY_RUN}; then
  log "DRY-RUN: skip DB update"
  exit 0
fi

SQL="
UPDATE systempreferences SET value='${OPAC_URL_SQL}' WHERE variable='OPACBaseURL';
UPDATE systempreferences SET value='${STAFF_URL_SQL}' WHERE variable='staffClientBaseURL';
SELECT variable, value FROM systempreferences
WHERE variable IN ('OPACBaseURL','staffClientBaseURL')
ORDER BY variable;
"

docker compose --env-file "${ENV_FILE}" -f "${PROJECT_ROOT}/docker-compose.yaml" exec -T \
  db mariadb -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" -e "${SQL}"

log "Done: domain system preferences"
