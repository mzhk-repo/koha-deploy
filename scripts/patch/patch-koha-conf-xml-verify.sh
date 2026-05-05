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
DB_NAME="${DB_NAME:-koha_library}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-koha_db}"
DB_PASS="${DB_PASS:?DB_PASS is required}"
MB_HOST="${MB_HOST:-rabbitmq}"
MB_PORT="${MB_PORT:-61613}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASS="${RABBITMQ_PASS:?RABBITMQ_PASS is required}"
SMTP_HOST="${SMTP_HOST:-localhost}"
SMTP_PORT="${SMTP_PORT:-25}"
SMTP_SSL_MODE="${SMTP_SSL_MODE:-disabled}"
KOHA_TRUSTED_PROXIES="${KOHA_TRUSTED_PROXIES:-127.0.0.1 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16}"

verify_xml_secret() {
  local tag="$1"
  local expected_env="$2"
  local range_start="${3:-}"
  local range_end="${4:-}"

  XML_SECRET_TAG="${tag}" \
  XML_SECRET_ENV="${expected_env}" \
  XML_SECRET_RANGE_START="${range_start}" \
  XML_SECRET_RANGE_END="${range_end}" \
    perl -0777 -ne '
      my $tag = $ENV{"XML_SECRET_TAG"};
      my $expected = $ENV{$ENV{"XML_SECRET_ENV"}};
      my $start = $ENV{"XML_SECRET_RANGE_START"} // "";
      my $end = $ENV{"XML_SECRET_RANGE_END"} // "";
      my $text = $_;

      if ($start ne "" && $end ne "") {
        $text =~ s/^.*?\Q$start\E/$start/s or exit 2;
        $text =~ s/\Q$end\E.*$/$end/s or exit 2;
      }

      $text =~ m{<\Q$tag\E>(.*?)</\Q$tag\E>}s or exit 2;
      my $actual = $1;
      $actual =~ s/^\s+|\s+$//g;
      exit($actual eq $expected ? 0 : 1);
    ' "${KOHA_CONF_FILE}"
}

grep -q "<database>${DB_NAME}</database>" "${KOHA_CONF_FILE}" || die "verify failed: DB database"
grep -q "<hostname>${DB_HOST}</hostname>" "${KOHA_CONF_FILE}" || die "verify failed: DB hostname"
grep -q "<port>${DB_PORT}</port>" "${KOHA_CONF_FILE}" || die "verify failed: DB port"
grep -q "<user>${DB_USER}</user>" "${KOHA_CONF_FILE}" || die "verify failed: DB user"
verify_xml_secret "pass" "DB_PASS" "<config>" "<tls>" || die "verify failed: DB password"
grep -q "<timezone>${KOHA_TIMEZONE}</timezone>" "${KOHA_CONF_FILE}" || die "verify failed: timezone"
grep -q "<memcached_servers>${MEMCACHED_SERVERS}</memcached_servers>" "${KOHA_CONF_FILE}" || die "verify failed: memcached_servers"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<hostname>${MB_HOST}</hostname>" || die "verify failed: message_broker hostname"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<port>${MB_PORT}</port>" || die "verify failed: message_broker port"
sed -n '/<message_broker>/,/<\/message_broker>/p' "${KOHA_CONF_FILE}" | grep -q "<username>${RABBITMQ_USER}</username>" || die "verify failed: message_broker username"
verify_xml_secret "password" "RABBITMQ_PASS" "<message_broker>" "</message_broker>" || die "verify failed: message_broker password"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<host>${SMTP_HOST}</host>" || die "verify failed: smtp host"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<port>${SMTP_PORT}</port>" || die "verify failed: smtp port"
sed -n '/<smtp_server>/,/<\/smtp_server>/p' "${KOHA_CONF_FILE}" | grep -q "<ssl_mode>${SMTP_SSL_MODE}</ssl_mode>" || die "verify failed: smtp ssl_mode"
grep -q "<koha_trusted_proxies>${KOHA_TRUSTED_PROXIES}</koha_trusted_proxies>" "${KOHA_CONF_FILE}" || die "verify failed: koha_trusted_proxies"

log "Verify OK: koha-conf.xml runtime values match .env"
