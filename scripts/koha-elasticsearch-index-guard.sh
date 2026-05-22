#!/usr/bin/env bash
# Script Purpose: Verify Koha Elasticsearch indexes after deploy and rebuild only when it is safe and necessary.
# Usage: ./scripts/koha-elasticsearch-index-guard.sh [--env-file FILE] [--wait-timeout SEC] [--dry-run] [--reindex-force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-}"
WAIT_TIMEOUT=300
DRY_RUN=false
REINDEX_FORCE=false

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./scripts/koha-elasticsearch-index-guard.sh [options]

Options:
  --env-file FILE       Path to env file (default: ORCHESTRATOR_ENV_FILE, fallback ./.env for dev)
  --wait-timeout SEC    Wait timeout for Elasticsearch availability (default: 300)
  --dry-run             Print intended rebuild action without running it
  --reindex-force       Force a full delete/rebuild of all Elasticsearch records
  --help                Show help

Environment:
  ORCHESTRATOR_ES_GUARD=smart|off|force
      smart: verify indexes and rebuild only for missing indexes or configured mismatch policy
      off:   skip all checks
      force: run a full delete/rebuild

  ORCHESTRATOR_ES_REINDEX_ON_MISMATCH=auto|warn|fail
      auto: rebuild when Elasticsearch is significantly behind DB or has stale docs
      warn: log count mismatches and continue
      fail: fail deploy on any count mismatch

  ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT=5
      Percentage threshold used by auto mode when ES docs are lower than DB rows.

  ORCHESTRATOR_ES_INDEXER_RESTART=true|false
      Restart koha-es-indexer after guard checks so the daemon reloads current Koha preferences.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || die "--env-file requires value"
      ENV_FILE="$1"
      ;;
    --wait-timeout)
      shift
      [ "$#" -gt 0 ] || die "--wait-timeout requires value"
      WAIT_TIMEOUT="$1"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --reindex-force)
      REINDEX_FORCE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

[[ "${WAIT_TIMEOUT}" =~ ^[0-9]+$ ]] || die "--wait-timeout must be numeric"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/orchestrator-env.sh"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/docker-runtime.sh"

is_true() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

load_runtime_context() {
  ENV_FILE="$(resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}")"
  KOHA_COMPOSE_FILE="$(docker_runtime_detect_compose_file "${PROJECT_ROOT}")"
  DOCKER_RUNTIME_COMPOSE_FILE="${KOHA_COMPOSE_FILE}"
  DOCKER_RUNTIME_ENV_FILE="${ENV_FILE}"
  export KOHA_COMPOSE_FILE DOCKER_RUNTIME_COMPOSE_FILE DOCKER_RUNTIME_ENV_FILE
  load_orchestrator_env_file "${ENV_FILE}"

  KOHA_INSTANCE="${KOHA_INSTANCE:-library}"
  ORCHESTRATOR_ES_GUARD="${ORCHESTRATOR_ES_GUARD:-smart}"
  ORCHESTRATOR_ES_REINDEX_ON_MISMATCH="${ORCHESTRATOR_ES_REINDEX_ON_MISMATCH:-auto}"
  ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT="${ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT:-5}"
  ORCHESTRATOR_ES_INDEXER_RESTART="${ORCHESTRATOR_ES_INDEXER_RESTART:-true}"

  case "${ORCHESTRATOR_ES_GUARD}" in
    smart|off|force) ;;
    *) die "unsupported ORCHESTRATOR_ES_GUARD=${ORCHESTRATOR_ES_GUARD} (expected: smart|off|force)" ;;
  esac

  case "${ORCHESTRATOR_ES_REINDEX_ON_MISMATCH}" in
    warn|auto|fail) ;;
    *) die "unsupported ORCHESTRATOR_ES_REINDEX_ON_MISMATCH=${ORCHESTRATOR_ES_REINDEX_ON_MISMATCH} (expected: warn|auto|fail)" ;;
  esac

  [[ "${ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT}" =~ ^[0-9]+$ ]] \
    || die "ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT must be numeric"
}

koha_sql_scalar() {
  local sql="$1"
  docker_runtime_exec koha koha-mysql "${KOHA_INSTANCE}" -N -B -e "${sql}" \
    | tr -d '\r' \
    | tail -n 1
}

es_http_status() {
  local path="$1"
  docker_runtime_exec es curl -s -o /dev/null -w '%{http_code}' "http://localhost:9200${path}" 2>/dev/null || true
}

es_json_count() {
  local index="$1"
  local body count

  body="$(docker_runtime_exec es curl -fsS "http://localhost:9200/${index}/_count" 2>/dev/null || true)"
  count="$(printf '%s\n' "${body}" | sed -nE 's/.*"count"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -n 1)"
  [[ "${count}" =~ ^[0-9]+$ ]] || die "cannot read Elasticsearch _count for index ${index}"
  printf '%s\n' "${count}"
}

wait_for_elasticsearch() {
  local elapsed=0 status

  log "Waiting for Elasticsearch API (timeout=${WAIT_TIMEOUT}s)"
  while [ "${elapsed}" -lt "${WAIT_TIMEOUT}" ]; do
    status="$(es_http_status "/")"
    if [ "${status}" = "200" ]; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  die "Elasticsearch API is not available within timeout"
}

run_rebuild() {
  local reason="$1"
  local mode="$2"
  local cmd=(koha-elasticsearch --rebuild -v)

  case "${mode}" in
    reset)
      cmd+=(--reset)
      ;;
    delete)
      cmd+=(--delete)
      ;;
    plain)
      ;;
    *)
      die "internal error: unknown rebuild mode=${mode}"
      ;;
  esac
  cmd+=("${KOHA_INSTANCE}")

  log "Elasticsearch rebuild required: ${reason}"
  log "Command: ${cmd[*]}"

  if ${DRY_RUN}; then
    log "DRY-RUN: skip Elasticsearch rebuild"
    return 0
  fi

  docker_runtime_exec koha "${cmd[@]}"
}

restart_es_indexer() {
  if ! is_true "${ORCHESTRATOR_ES_INDEXER_RESTART}"; then
    log "Skip koha-es-indexer restart (ORCHESTRATOR_ES_INDEXER_RESTART=${ORCHESTRATOR_ES_INDEXER_RESTART})"
    return 0
  fi

  log "Restarting koha-es-indexer for ${KOHA_INSTANCE}"
  if ${DRY_RUN}; then
    log "DRY-RUN: skip koha-es-indexer restart"
    return 0
  fi

  case "$(docker_runtime_mode)" in
    swarm)
      if docker service inspect "${STACK_NAME:-koha}_koha-es-indexer" >/dev/null 2>&1; then
        docker service update --force "${STACK_NAME:-koha}_koha-es-indexer" >/dev/null
        docker_runtime_wait_for_swarm_container koha-es-indexer "${WAIT_TIMEOUT}" \
          || die "koha-es-indexer service did not start within timeout"
        log "Managed koha-es-indexer service restarted"
        return 0
      fi
      ;;
    compose)
      local indexer_cid
      indexer_cid="$(docker compose --env-file "${ENV_FILE}" -f "${KOHA_COMPOSE_FILE}" ps -q koha-es-indexer 2>/dev/null || true)"
      if [ -n "${indexer_cid}" ]; then
        docker compose --env-file "${ENV_FILE}" -f "${KOHA_COMPOSE_FILE}" restart koha-es-indexer >/dev/null
        log "Managed koha-es-indexer service restarted"
        return 0
      fi
      ;;
  esac

  warn "Managed koha-es-indexer service not found; falling back to legacy in-container daemon"
  docker_runtime_exec koha koha-es-indexer --restart "${KOHA_INSTANCE}"
  docker_runtime_exec koha koha-es-indexer --status "${KOHA_INSTANCE}"
}

allowed_lag() {
  local db_count="$1"
  local threshold_percent="$2"
  local lag

  lag=$(( db_count * threshold_percent / 100 ))
  printf '%s\n' "${lag}"
}

MISMATCH_REBUILD_MODE=""
MISMATCH_REBUILD_REASON=""

remember_rebuild() {
  local reason="$1"
  local mode="$2"

  if [ -z "${MISMATCH_REBUILD_MODE}" ]; then
    MISMATCH_REBUILD_MODE="${mode}"
    MISMATCH_REBUILD_REASON="${reason}"
    return 0
  fi

  if [ "${mode}" = "delete" ] && [ "${MISMATCH_REBUILD_MODE}" != "delete" ]; then
    MISMATCH_REBUILD_MODE="${mode}"
  fi
  MISMATCH_REBUILD_REASON="${MISMATCH_REBUILD_REASON}; ${reason}"
}

handle_count_mismatch() {
  local label="$1"
  local db_count="$2"
  local es_count="$3"
  local delta allowed

  if [ "${db_count}" -eq "${es_count}" ]; then
    log "${label}: DB=${db_count}, ES=${es_count}; OK"
    return 0
  fi

  warn "${label}: DB=${db_count}, ES=${es_count}; mismatch detected"

  case "${ORCHESTRATOR_ES_REINDEX_ON_MISMATCH}" in
    warn)
      return 0
      ;;
    fail)
      die "${label}: count mismatch and ORCHESTRATOR_ES_REINDEX_ON_MISMATCH=fail"
      ;;
    auto)
      if [ "${es_count}" -gt "${db_count}" ]; then
        remember_rebuild "${label} has stale Elasticsearch docs (ES > DB)" delete
        return 0
      fi

      delta=$((db_count - es_count))
      allowed="$(allowed_lag "${db_count}" "${ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT}")"
      if [ "${delta}" -gt "${allowed}" ]; then
        remember_rebuild "${label} Elasticsearch docs lag DB by ${delta}, allowed lag=${allowed}" plain
      else
        warn "${label}: lag ${delta} is within threshold ${ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT}% (allowed=${allowed}); skip rebuild"
      fi
      ;;
  esac
}

main() {
  local search_engine biblios_index authorities_index
  local biblio_db_count authority_db_count biblio_es_count authority_es_count
  local biblio_status authority_status

  load_runtime_context

  if [ "${ORCHESTRATOR_ES_GUARD}" = "off" ]; then
    log "Elasticsearch index guard disabled (ORCHESTRATOR_ES_GUARD=off)"
    exit 0
  fi

  if ! is_true "${USE_ELASTICSEARCH:-true}"; then
    log "Elasticsearch disabled by USE_ELASTICSEARCH=${USE_ELASTICSEARCH:-}; skip index guard"
    exit 0
  fi

  search_engine="$(koha_sql_scalar "SELECT COALESCE(value,'') FROM systempreferences WHERE variable='SearchEngine';")"
  if [ "${search_engine}" != "Elasticsearch" ]; then
    log "Koha SearchEngine=${search_engine:-unset}; skip Elasticsearch index guard"
    exit 0
  fi

  wait_for_elasticsearch

  biblios_index="koha_${KOHA_INSTANCE}_biblios"
  authorities_index="koha_${KOHA_INSTANCE}_authorities"

  if [ "${ORCHESTRATOR_ES_GUARD}" = "force" ] || ${REINDEX_FORCE}; then
    if ${REINDEX_FORCE}; then
      run_rebuild "forced by --reindex-force" delete
    else
      run_rebuild "forced by ORCHESTRATOR_ES_GUARD=force" delete
    fi
    restart_es_indexer
    exit 0
  fi

  biblio_status="$(es_http_status "/${biblios_index}")"
  authority_status="$(es_http_status "/${authorities_index}")"

  if [ "${biblio_status}" != "200" ] || [ "${authority_status}" != "200" ]; then
    run_rebuild "missing index(es): ${biblios_index}=${biblio_status}, ${authorities_index}=${authority_status}" reset
    restart_es_indexer
    exit 0
  fi

  biblio_db_count="$(koha_sql_scalar "SELECT COUNT(*) FROM biblio;")"
  authority_db_count="$(koha_sql_scalar "SELECT COUNT(*) FROM auth_header;")"
  biblio_es_count="$(es_json_count "${biblios_index}")"
  authority_es_count="$(es_json_count "${authorities_index}")"

  handle_count_mismatch "Biblios" "${biblio_db_count}" "${biblio_es_count}"
  handle_count_mismatch "Authorities" "${authority_db_count}" "${authority_es_count}"

  if [ -n "${MISMATCH_REBUILD_MODE}" ]; then
    run_rebuild "${MISMATCH_REBUILD_REASON}" "${MISMATCH_REBUILD_MODE}"
  fi

  restart_es_indexer

  log "Elasticsearch index guard completed"
}

main "$@"
