#!/usr/bin/env bash
# Script Purpose: Verify Memcached and set Koha SessionStorage.
# Usage: ./scripts/patch/patch-koha-session-storage.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-session-storage.sh [options]

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

SESSION_STORAGE="${KOHA_SESSION_STORAGE:-mysql}"
case "${SESSION_STORAGE}" in
  mysql|memcached) ;;
  *) die "KOHA_SESSION_STORAGE must be mysql or memcached (got: ${SESSION_STORAGE})" ;;
esac

log "Setting Koha SessionStorage=${SESSION_STORAGE}"

if ${DRY_RUN}; then
  log "DRY-RUN: skip Memcached probe and system preference update"
  exit 0
fi

if [ "${SESSION_STORAGE}" = "memcached" ]; then
  probe_code='my $cache = Koha::Caches->get_instance; my $key = "koha_session_storage_probe_$$"; my $value = "ok"; $cache->set_in_cache($key, $value); die "Memcached set/get probe failed\n" unless ($cache->get_from_cache($key) // "") eq $value; $cache->clear_from_cache($key); die "Memcached delete probe failed\n" if defined $cache->get_from_cache($key); print "Memcached session probe ok\n";'
  docker_runtime_exec koha koha-shell "${KOHA_INSTANCE:-library}" -c \
    "perl -MKoha::Caches -e '${probe_code}'"
fi

docker_runtime_exec koha koha-shell "${KOHA_INSTANCE:-library}" -c \
  "perl -MC4::Context -e 'C4::Context->set_preference(\"SessionStorage\", \"${SESSION_STORAGE}\"); die \"SessionStorage verify failed\\n\" unless C4::Context->preference(\"SessionStorage\") eq \"${SESSION_STORAGE}\"; print \"SessionStorage=${SESSION_STORAGE}\\n\";'"

log "Done: SessionStorage=${SESSION_STORAGE}"
