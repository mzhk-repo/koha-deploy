#!/usr/bin/env bash
# Script Purpose: Patch main DB connection block in live koha-conf.xml from .env values.
# Usage: ./scripts/patch/patch-koha-conf-xml-db.sh [--env-file FILE] [--wait-timeout SEC] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-conf-xml-db.sh [options]

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

PATCH_DB_NAME="${DB_NAME:-koha_library}"
PATCH_DB_HOST="${DB_HOST:-${MYSQL_SERVER:-db}}"
PATCH_DB_PORT="${DB_PORT:-3306}"
PATCH_DB_USER="${DB_USER:-${MYSQL_USER:-koha_db}}"
PATCH_DB_PASS="${DB_PASS:?DB_PASS is required}"

[[ "${PATCH_DB_PORT}" =~ ^[0-9]+$ ]] || die "DB_PORT must be numeric"

log "Patching DB connection in ${KOHA_CONF_FILE} -> ${PATCH_DB_USER}@${PATCH_DB_HOST}:${PATCH_DB_PORT}/${PATCH_DB_NAME}"

if ! ${DRY_RUN}; then
  export PATCH_DB_NAME PATCH_DB_HOST PATCH_DB_PORT PATCH_DB_USER PATCH_DB_PASS
  perl -0777 -i -pe '
    sub esc {
      my ($v) = @_;
      $v = "" unless defined $v;
      $v =~ s/&/&amp;/g;
      $v =~ s/</&lt;/g;
      $v =~ s/>/&gt;/g;
      return $v;
    }

    my $d = esc($ENV{"PATCH_DB_NAME"});
    my $h = esc($ENV{"PATCH_DB_HOST"});
    my $p = esc($ENV{"PATCH_DB_PORT"});
    my $u = esc($ENV{"PATCH_DB_USER"});
    my $w = esc($ENV{"PATCH_DB_PASS"});

    my $block = " <db_scheme>mysql</db_scheme>\n"
      . " <database>${d}</database>\n"
      . " <hostname>${h}</hostname>\n"
      . " <port>${p}</port>\n"
      . " <user>${u}</user>\n"
      . " <pass>${w}</pass>";

    s{<db_scheme>mysql</db_scheme>\s*<database>.*?</database>\s*<hostname>.*?</hostname>\s*<port>.*?</port>\s*<user>.*?</user>\s*<pass>.*?</pass>}{$block}s
      or die "main DB block not found\n";
  ' "${KOHA_CONF_FILE}"
fi

if ! ${DRY_RUN}; then
  grep -q "<database>${PATCH_DB_NAME}</database>" "${KOHA_CONF_FILE}" || die "DB database verify failed"
  grep -q "<hostname>${PATCH_DB_HOST}</hostname>" "${KOHA_CONF_FILE}" || die "DB host verify failed"
  grep -q "<port>${PATCH_DB_PORT}</port>" "${KOHA_CONF_FILE}" || die "DB port verify failed"
  grep -q "<user>${PATCH_DB_USER}</user>" "${KOHA_CONF_FILE}" || die "DB user verify failed"
fi

log "Done: db connection"
