#!/usr/bin/env bash
# Script Purpose: Patch <smtp_server> block in live koha-conf.xml from .env SMTP values.
# Usage: ./scripts/patch/patch-koha-conf-xml-smtp.sh [--env-file FILE] [--wait-timeout SEC] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-conf-xml-smtp.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --wait-timeout SEC  Wait timeout for koha-conf.xml (default: 300)
  --dry-run           Print actions only
  --no-wait           Do not wait for file creation
  --help              Show help
USAGE
}

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

prepare_live_context

PATCH_SMTP_HOST="${SMTP_HOST:-localhost}"
PATCH_SMTP_PORT="${SMTP_PORT:-25}"
PATCH_SMTP_TIMEOUT="${SMTP_TIMEOUT:-120}"
PATCH_SMTP_SSL_MODE="${SMTP_SSL_MODE:-disabled}"
PATCH_SMTP_USER="${SMTP_USER_NAME:-}"
PATCH_SMTP_PASS="${SMTP_PASSWORD:-}"
PATCH_SMTP_DEBUG="${SMTP_DEBUG:-0}"
ADMIN_EMAIL="${KOHA_ADMIN_EMAIL_ADDRESS:-}"

if [ -n "${ADMIN_EMAIL}" ]; then
  [[ "${ADMIN_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] || die "KOHA_ADMIN_EMAIL_ADDRESS must be a valid email address"
fi

[[ "${PATCH_SMTP_PORT}" =~ ^[0-9]+$ ]] || die "SMTP_PORT must be numeric"
[[ "${PATCH_SMTP_TIMEOUT}" =~ ^[0-9]+$ ]] || die "SMTP_TIMEOUT must be numeric"
[[ "${PATCH_SMTP_DEBUG}" =~ ^[0-9]+$ ]] || die "SMTP_DEBUG must be numeric"
case "${PATCH_SMTP_SSL_MODE}" in
  disabled|ssl|starttls) ;;
  *) die "SMTP_SSL_MODE must be one of: disabled, ssl, starttls" ;;
esac

log "Patching smtp_server in ${KOHA_CONF_FILE} -> ${PATCH_SMTP_HOST}:${PATCH_SMTP_PORT} (${PATCH_SMTP_SSL_MODE})"

if ! ${DRY_RUN}; then
  export PATCH_SMTP_HOST PATCH_SMTP_PORT PATCH_SMTP_TIMEOUT PATCH_SMTP_SSL_MODE PATCH_SMTP_USER PATCH_SMTP_PASS PATCH_SMTP_DEBUG
  perl -0777 -i -pe '
    sub esc {
      my ($v) = @_;
      $v = "" unless defined $v;
      $v =~ s/&/&amp;/g;
      $v =~ s/</&lt;/g;
      $v =~ s/>/&gt;/g;
      return $v;
    }

    my $h = esc($ENV{"PATCH_SMTP_HOST"});
    my $p = esc($ENV{"PATCH_SMTP_PORT"});
    my $t = esc($ENV{"PATCH_SMTP_TIMEOUT"});
    my $m = esc($ENV{"PATCH_SMTP_SSL_MODE"});
    my $u = esc($ENV{"PATCH_SMTP_USER"});
    my $w = esc($ENV{"PATCH_SMTP_PASS"});
    my $d = esc($ENV{"PATCH_SMTP_DEBUG"});

    my $block = " <smtp_server>\n"
      . "    <host>${h}</host>\n"
      . "    <port>${p}</port>\n"
      . "    <timeout>${t}</timeout>\n"
      . "    <ssl_mode>${m}</ssl_mode>\n"
      . "    <user_name>${u}</user_name>\n"
      . "    <password>${w}</password>\n"
      . "    <debug>${d}</debug>\n"
      . " </smtp_server>";

    s{<smtp_server>.*?</smtp_server>}{$block}s or die "smtp_server block not found\n";
  ' "${KOHA_CONF_FILE}"
fi

if ! ${DRY_RUN}; then
  grep -q "<host>${PATCH_SMTP_HOST}</host>" "${KOHA_CONF_FILE}" || die "smtp host verify failed"
  grep -q "<port>${PATCH_SMTP_PORT}</port>" "${KOHA_CONF_FILE}" || die "smtp port verify failed"
  grep -q "<ssl_mode>${PATCH_SMTP_SSL_MODE}</ssl_mode>" "${KOHA_CONF_FILE}" || die "smtp ssl_mode verify failed"
  if [ -n "${ADMIN_EMAIL}" ]; then
    docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE:-library}" -e \
      "UPDATE systempreferences SET value='${ADMIN_EMAIL}' WHERE variable='KohaAdminEmailAddress';"
    actual_email="$(docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE:-library}" -N -B -e \
      "SELECT value FROM systempreferences WHERE variable='KohaAdminEmailAddress';")"
    [ "${actual_email}" = "${ADMIN_EMAIL}" ] || die "KohaAdminEmailAddress verification failed"
    docker_runtime_exec koha koha-shell "${KOHA_INSTANCE:-library}" -c \
      'perl -MKoha::Caches -e "Koha::Caches->get_instance->flush_all"'
  fi
fi

log "Done: smtp_server"
