#!/usr/bin/env bash
# Script Purpose: Verify critical live koha-conf.xml values against current .env.
# Usage: ./scripts/patch/patch-koha-conf-xml-verify.sh [--env-file FILE] [--wait-timeout SEC]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-conf-xml-verify.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --wait-timeout SEC  Wait timeout for koha-conf.xml (default: 300)
  --no-wait           Do not wait for file creation
  --help              Show help
USAGE
}

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

# verify is read-only; force dry mode to skip backup logic in helper
# shellcheck disable=SC2034
DRY_RUN=true
prepare_live_context

KOHA_TIMEZONE="${KOHA_TIMEZONE:-Europe/Kyiv}"
MEMCACHED_SERVERS="${MEMCACHED_SERVERS:-memcached:11211}"
MB_HOST="${MB_HOST:-rabbitmq}"
MB_PORT="${MB_PORT:-61613}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
SMTP_HOST="${SMTP_HOST:-localhost}"
SMTP_PORT="${SMTP_PORT:-25}"
SMTP_SSL_MODE="${SMTP_SSL_MODE:-disabled}"

grep -q "<timezone>${KOHA_TIMEZONE}</timezone>" "${KOHA_CONF_FILE}" || die "verify failed: timezone"
grep -q "<memcached_servers>${MEMCACHED_SERVERS}</memcached_servers>" "${KOHA_CONF_FILE}" || die "verify failed: memcached_servers"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<hostname>${MB_HOST}</hostname>" || die "verify failed: message_broker hostname"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<port>${MB_PORT}</port>" || die "verify failed: message_broker port"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<username>${RABBITMQ_USER}</username>" || die "verify failed: message_broker username"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<host>${SMTP_HOST}</host>" || die "verify failed: smtp host"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<port>${SMTP_PORT}</port>" || die "verify failed: smtp port"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<ssl_mode>${SMTP_SSL_MODE}</ssl_mode>" || die "verify failed: smtp ssl_mode"

log "Verify OK: koha-conf.xml runtime values match .env"
