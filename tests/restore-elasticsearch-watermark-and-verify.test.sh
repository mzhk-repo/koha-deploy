#!/usr/bin/env bash
# Regression test: restore.sh and koha-elasticsearch-index-guard.sh configure ES disk watermarks,
# rebuild error trapping, and strict verify_restore check.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_pattern() {
  local file="$1"
  local pattern="$2"

  grep -Fq -- "${pattern}" "${file}" || {
    printf 'missing required pattern in %s: %s\n' "${file}" "${pattern}" >&2
    exit 1
  }
}

# 1. Check docker-compose.yml has cluster routing watermark settings for es
compose_file="${PROJECT_ROOT}/docker-compose.yml"
require_pattern "${compose_file}" 'cluster.routing.allocation.disk.threshold_enabled: "true"'
require_pattern "${compose_file}" 'cluster.routing.allocation.disk.watermark.low: ${ES_DISK_WATERMARK_LOW:-95%}'
require_pattern "${compose_file}" 'cluster.routing.allocation.disk.watermark.high: ${ES_DISK_WATERMARK_HIGH:-97%}'
require_pattern "${compose_file}" 'cluster.routing.allocation.disk.watermark.flood_stage: ${ES_DISK_WATERMARK_FLOOD_STAGE:-98%}'

# 2. Check restore.sh has ensure_es_cluster_settings and error checking
restore_file="${PROJECT_ROOT}/scripts/restore.sh"
require_pattern "${restore_file}" 'ensure_es_cluster_settings'
require_pattern "${restore_file}" 'Something went wrong rebuilding indexes'
require_pattern "${restore_file}" 'number_of_replicas":0'
require_pattern "${restore_file}" 'Elasticsearch biblios index has 0 records but database has'

# 3. Check koha-elasticsearch-index-guard.sh has ensure_es_cluster_settings and error checking
guard_file="${PROJECT_ROOT}/scripts/koha-elasticsearch-index-guard.sh"
require_pattern "${guard_file}" 'ensure_es_cluster_settings'
require_pattern "${guard_file}" 'Something went wrong rebuilding indexes'
require_pattern "${guard_file}" 'number_of_replicas":0'

# 4. Check .env.example documents the watermark variables
example_file="${PROJECT_ROOT}/.env.example"
require_pattern "${example_file}" 'ES_DISK_WATERMARK_LOW=95%'
require_pattern "${example_file}" 'ES_DISK_WATERMARK_HIGH=97%'
require_pattern "${example_file}" 'ES_DISK_WATERMARK_FLOOD_STAGE=98%'

printf 'PASS: Elasticsearch watermark configuration and strict restore verification verified\n'
