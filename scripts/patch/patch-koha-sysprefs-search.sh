#!/usr/bin/env bash
# Script Purpose: Set Koha search engine system preference from env and flush Koha cache.
# Usage: ./scripts/patch/patch-koha-sysprefs-search.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-sysprefs-search.sh [options]

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

is_true() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

sql_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\'/\'\'}"
  printf '%s' "${v}"
}

SEARCH_ENGINE="${KOHA_SEARCH_ENGINE:-}"
if [ -z "${SEARCH_ENGINE}" ]; then
  if is_true "${USE_ELASTICSEARCH:-true}"; then
    SEARCH_ENGINE="Elasticsearch"
  else
    SEARCH_ENGINE="Zebra"
  fi
fi

case "${SEARCH_ENGINE}" in
  Elasticsearch|Zebra) ;;
  *) die "KOHA_SEARCH_ENGINE must be Elasticsearch or Zebra (got: ${SEARCH_ENGINE})" ;;
esac

SEARCH_ENGINE_SQL="$(sql_escape "${SEARCH_ENGINE}")"

log "Patching systempreferences: SearchEngine=${SEARCH_ENGINE}"

if ${DRY_RUN}; then
  log "DRY-RUN: skip DB update and Koha cache flush"
  exit 0
fi

SQL="
INSERT INTO systempreferences (variable, value)
VALUES ('SearchEngine', '${SEARCH_ENGINE_SQL}')
ON DUPLICATE KEY UPDATE value=VALUES(value);
SELECT variable, value FROM systempreferences
WHERE variable IN ('SearchEngine')
ORDER BY variable;
"

docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE:-library}" -e "${SQL}"

log "Flushing Koha cache after SearchEngine syspref update"
docker_runtime_exec koha koha-shell "${KOHA_INSTANCE:-library}" -c \
  'perl -MKoha::Caches -e "Koha::Caches->get_instance->flush_all; print qq(cache flush ok\n)"'

log "Done: search system preferences"
