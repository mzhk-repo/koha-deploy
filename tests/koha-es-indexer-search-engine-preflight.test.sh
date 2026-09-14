#!/usr/bin/env bash
# Regression test: the ES indexer repairs SearchEngine before starting its daemon.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${PROJECT_ROOT}/docker-compose.yml"
swarm_file="${PROJECT_ROOT}/docker-compose.swarm.yml"

require_pattern() {
  local file="$1"
  local pattern="$2"

  grep -Fq -- "${pattern}" "${file}" || {
    printf 'missing required preflight fragment in %s: %s\n' "${file}" "${pattern}" >&2
    exit 1
  }
}

require_pattern "${compose_file}" 'INSERT INTO systempreferences (variable, value) VALUES ('"'"'SearchEngine'"'"', '"'"'$$expected_search_engine'"'"') ON DUPLICATE KEY UPDATE value=VALUES(value);'
require_pattern "${compose_file}" 'Koha::Caches->get_instance->flush_all;'
require_pattern "${compose_file}" 'wait_until "Koha SearchEngine=$$expected_search_engine" ensure_koha_search_engine'
require_pattern "${compose_file}" 'KOHA_SEARCH_ENGINE: ${KOHA_SEARCH_ENGINE:-Elasticsearch}'
require_pattern "${swarm_file}" 'KOHA_SEARCH_ENGINE: ${KOHA_SEARCH_ENGINE:-Elasticsearch}'

preflight_line="$(grep -nF 'wait_until "Koha SearchEngine=$$expected_search_engine" ensure_koha_search_engine' "${compose_file}" | cut -d: -f1)"
daemon_line="$(grep -nF '/usr/share/koha/bin/workers/es_indexer_daemon.pl' "${compose_file}" | head -n 1 | cut -d: -f1)"

[[ -n "${preflight_line}" && -n "${daemon_line}" && "${preflight_line}" -lt "${daemon_line}" ]] || {
  printf 'SearchEngine preflight must run before es_indexer_daemon.pl\n' >&2
  exit 1
}

printf 'PASS: koha-es-indexer repairs SearchEngine before daemon startup\n'
