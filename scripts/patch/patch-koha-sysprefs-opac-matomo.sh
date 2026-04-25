#!/usr/bin/env bash
# Script Purpose: Set Koha OpacCustomJS system preference from managed Matomo tracker snippet.
# Usage: ./scripts/patch/patch-koha-sysprefs-opac-matomo.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-sysprefs-opac-matomo.sh [options]

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

MATOMO_BASE_URL="${MATOMO_BASE_URL:-https://matomo.pinokew.buzz/}"
MATOMO_SITE_ID="${MATOMO_SITE_ID:-1}"
MATOMO_SNIPPET_FILE="${MATOMO_SNIPPET_FILE:-docs/snippets/koha-opac-tracker.js}"
KOHA_OPAC_JS_PREF_KEY="${KOHA_OPAC_JS_PREF_KEY:-OPACUserJS}"
MATOMO_TRACKER_URL="${MATOMO_TRACKER_URL:-}"
MATOMO_SITE_SEARCH_QUERY_PARAM="${MATOMO_SITE_SEARCH_QUERY_PARAM:-q}"
MATOMO_DEVICE_DIMENSION_ID="${MATOMO_DEVICE_DIMENSION_ID:-1}"

[[ "${MATOMO_SITE_ID}" =~ ^[0-9]+$ ]] || die "MATOMO_SITE_ID must be numeric"
[[ "${MATOMO_DEVICE_DIMENSION_ID}" =~ ^[0-9]+$ ]] || die "MATOMO_DEVICE_DIMENSION_ID must be numeric"

case "${MATOMO_BASE_URL}" in
  */) ;;
  *) MATOMO_BASE_URL="${MATOMO_BASE_URL}/" ;;
esac

if [ -z "${MATOMO_TRACKER_URL}" ]; then
  MATOMO_TRACKER_URL="${MATOMO_BASE_URL}matomo.php"
fi

SOURCE_PATH="${MATOMO_SNIPPET_FILE}"
if [[ "${SOURCE_PATH}" != /* ]]; then
  SOURCE_PATH="${PROJECT_ROOT}/${SOURCE_PATH}"
fi
[ -f "${SOURCE_PATH}" ] || die "Matomo snippet source file not found: ${SOURCE_PATH}"

tmp_js="$(mktemp)"
trap 'rm -f "${tmp_js}"' EXIT

cp -a "${SOURCE_PATH}" "${tmp_js}"
sed -i "s|__MATOMO_BASE_URL__|${MATOMO_BASE_URL}|g" "${tmp_js}"
sed -i "s|__MATOMO_SITE_ID__|${MATOMO_SITE_ID}|g" "${tmp_js}"
sed -i "s|__MATOMO_TRACKER_URL__|${MATOMO_TRACKER_URL}|g" "${tmp_js}"
sed -i "s|__MATOMO_SITE_SEARCH_QUERY_PARAM__|${MATOMO_SITE_SEARCH_QUERY_PARAM}|g" "${tmp_js}"
sed -i "s|__MATOMO_DEVICE_DIMENSION_ID__|${MATOMO_DEVICE_DIMENSION_ID}|g" "${tmp_js}"

js_b64="$(base64 -w0 "${tmp_js}")"

log "Patching systempreferences: ${KOHA_OPAC_JS_PREF_KEY} from ${SOURCE_PATH} (MATOMO_BASE_URL=${MATOMO_BASE_URL}, MATOMO_TRACKER_URL=${MATOMO_TRACKER_URL}, MATOMO_SITE_ID=${MATOMO_SITE_ID})"

if ${DRY_RUN}; then
  log "DRY-RUN: skip DB update"
  exit 0
fi

SQL="
SET @js = FROM_BASE64('${js_b64}');
UPDATE systempreferences SET value=@js WHERE variable='${KOHA_OPAC_JS_PREF_KEY}';
SELECT variable, LENGTH(value) AS value_len FROM systempreferences WHERE variable='${KOHA_OPAC_JS_PREF_KEY}';
"

docker_runtime_exec db mariadb -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" -e "${SQL}"

log "Done: ${KOHA_OPAC_JS_PREF_KEY} Matomo snippet"
