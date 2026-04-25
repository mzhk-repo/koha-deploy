#!/usr/bin/env bash
# Script Purpose: Restore Koha from backup set (full restore, optional PITR, verify and reindex workflow).
# Usage: Run on host: ./scripts/restore.sh --source DIR [--dry-run|--pitr-datetime ...].
set -euo pipefail
umask 027

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT_ARG=""

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

is_true() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

load_env() {
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/lib/autonomous-env.sh"
  ENVIRONMENT_ARG="$(autonomous_env_arg_from_cli "$@")"
  load_autonomous_env "${PROJECT_ROOT}" "${ENVIRONMENT_ARG}"
}

usage() {
  cat <<USAGE
Usage: ./scripts/restore.sh [options]

Options:
  --source DIR                 Backup directory to restore from
  --dry-run                    Verify backup set only, do not restore
  --pitr-datetime "YYYY-MM-DD HH:MM:SS"
                               Apply binlogs up to timestamp
  --restore-es-data            Restore es_data.tar.gz (default: false)
  --restore-logs               Restore koha_logs.tar.gz (default: false)
  --skip-reindex               Skip koha-elasticsearch --rebuild
  --no-verify                  Skip post-restore verification
  --yes                        Do not wait 5 seconds confirmation window
  --env dev|prod               Environment to decrypt (default: SERVER_ENV)
  --help                       Show this help
USAGE
}

wait_service_healthy() {
  local service="$1"
  local timeout="${2:-300}"
  local elapsed=0
  local cid status

  cid="$(docker compose ps -q "${service}")"
  [ -n "${cid}" ] || die "Service not found in compose: ${service}"

  while [ "${elapsed}" -lt "${timeout}" ]; do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${cid}" 2>/dev/null || true)"
    case "${status}" in
      healthy|running)
        log "${service}: ${status}"
        return 0
        ;;
      unhealthy|exited|dead)
        docker compose logs --tail=120 "${service}" || true
        die "Service unhealthy: ${service} (${status})"
        ;;
    esac
    sleep 3
    elapsed=$((elapsed + 3))
  done

  docker compose logs --tail=120 "${service}" || true
  die "Timeout waiting for ${service} healthy (${timeout}s)"
}

detect_sql_dump() {
  local sql_plain="${RESTORE_SOURCE_DIR}/${DB_NAME}.sql"
  local sql_gz="${RESTORE_SOURCE_DIR}/${DB_NAME}.sql.gz"

  if [ -f "${sql_plain}" ]; then
    SQL_DUMP_FILE="${sql_plain}"
  elif [ -f "${sql_gz}" ]; then
    SQL_DUMP_FILE="${sql_gz}"
  else
    die "SQL dump missing: expected ${sql_plain} or ${sql_gz}"
  fi
}

verify_archive() {
  local archive="$1"
  [ -f "${archive}" ] || return 0
  gzip -t "${archive}"
  tar -tzf "${archive}" >/dev/null
}

verify_backup_set() {
  [ -d "${RESTORE_SOURCE_DIR}" ] || die "Backup directory not found: ${RESTORE_SOURCE_DIR}"
  detect_sql_dump

  if [ -f "${RESTORE_SOURCE_DIR}/SHA256SUMS" ]; then
    (cd "${RESTORE_SOURCE_DIR}" && sha256sum -c SHA256SUMS)
  else
    warn "SHA256SUMS missing in backup set, integrity check is partial"
  fi

  verify_archive "${RESTORE_SOURCE_DIR}/koha_config.tar.gz"
  verify_archive "${RESTORE_SOURCE_DIR}/koha_data.tar.gz"
  verify_archive "${RESTORE_SOURCE_DIR}/koha_logs.tar.gz"
  verify_archive "${RESTORE_SOURCE_DIR}/es_data.tar.gz"
  verify_archive "${RESTORE_SOURCE_DIR}/mariadb_binlogs.tar.gz"

  if [[ "${SQL_DUMP_FILE}" == *.gz ]]; then
    gzip -t "${SQL_DUMP_FILE}"
  else
    [ -s "${SQL_DUMP_FILE}" ] || die "SQL dump is empty: ${SQL_DUMP_FILE}"
  fi
}

wipe_bind_path() {
  local path="$1"
  [ -n "${path}" ] || return 0
  [ -d "${path}" ] || mkdir -p "${path}"
  docker run --rm -v "${path}:/target" alpine sh -ec '
    set -eu
    find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  '
}

restore_archive_to_path() {
  local archive="$1"
  local dst="$2"
  local uid="$3"
  local gid="$4"

  if [ ! -f "${archive}" ]; then
    warn "Archive not found, skip: ${archive}"
    return 0
  fi

  [ -d "${dst}" ] || mkdir -p "${dst}"
  docker run --rm \
    -e RESTORE_UID="${uid}" \
    -e RESTORE_GID="${gid}" \
    -v "${dst}:/target" \
    -v "${archive}:/backup/archive.tar.gz:ro" \
    alpine sh -ec '
      set -eu
      find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      tar -xzf /backup/archive.tar.gz -C /target
      chown -R "${RESTORE_UID}:${RESTORE_GID}" /target
    '
}

normalize_koha_conf_permissions() {
  docker run --rm -v "${VOL_KOHA_CONF}:/target" alpine sh -ec '
    set -eu
    find /target -type d -exec chmod 2775 {} +
    find /target -type f -exec chmod 640 {} +
  '
}

normalize_koha_conf_memcached() {
  local memcached_servers="${MEMCACHED_SERVERS:-memcached:11211}"
  local conf_file="${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml"

  if [ ! -f "${conf_file}" ]; then
    conf_file="$(find "${VOL_KOHA_CONF}" -maxdepth 3 -type f -name koha-conf.xml | head -n1 || true)"
  fi

  if [ -z "${conf_file}" ] || [ ! -f "${conf_file}" ]; then
    warn "koha-conf.xml not found, skip memcached normalization"
    return 0
  fi

  local esc
  esc="$(printf '%s' "${memcached_servers}" | sed 's/[\\/&]/\\\\&/g')"
  sed -Ei "s#(<memcached_servers>)[^<]*(</memcached_servers>)#\\1${esc}\\2#" "${conf_file}" || true
  chown "${KOHA_CONF_UID}:${KOHA_CONF_GID}" "${conf_file}" || true
  chmod 640 "${conf_file}" || true
  log "koha-conf.xml memcached_servers => ${memcached_servers}"
}

import_sql_dump() {
  log "Import SQL dump: ${SQL_DUMP_FILE}"
  docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" -e DB_NAME="${DB_NAME}" db sh -ec '
    mariadb -uroot -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  '

  if [[ "${SQL_DUMP_FILE}" == *.gz ]]; then
    gzip -dc "${SQL_DUMP_FILE}" | docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" -e DB_NAME="${DB_NAME}" db sh -ec '
      mariadb -uroot -p"${DB_ROOT_PASS}" "${DB_NAME}"
    '
  else
    docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" -e DB_NAME="${DB_NAME}" db sh -ec '
      mariadb -uroot -p"${DB_ROOT_PASS}" "${DB_NAME}"
    ' < "${SQL_DUMP_FILE}"
  fi
}

apply_pitr() {
  [ -n "${PITR_TARGET_DATETIME}" ] || return 0

  local archive="${RESTORE_SOURCE_DIR}/mariadb_binlogs.tar.gz"
  [ -f "${archive}" ] || die "PITR requested but mariadb_binlogs.tar.gz is missing"

  local pitr_tmp
  pitr_tmp="$(mktemp -d /tmp/koha-pitr-XXXXXX)"
  trap 'rm -rf "${pitr_tmp}"' RETURN

  tar -xzf "${archive}" -C "${pitr_tmp}"

  local start_file=""
  local start_pos=""
  if [ -f "${RESTORE_SOURCE_DIR}/pitr_master_status.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${RESTORE_SOURCE_DIR}/pitr_master_status.env" || true
    start_file="${PITR_START_FILE:-}"
    start_pos="${PITR_START_POS:-}"
  fi

  local db_cid
  db_cid="$(docker compose ps -q db)"
  [ -n "${db_cid}" ] || die "Cannot resolve db container id for PITR"

  docker compose exec -T db sh -ec 'rm -rf /tmp/koha-pitr-binlogs && mkdir -p /tmp/koha-pitr-binlogs'
  docker cp "${pitr_tmp}/." "${db_cid}:/tmp/koha-pitr-binlogs/"

  docker compose exec -T \
    -e DB_ROOT_PASS="${DB_ROOT_PASS}" \
    -e DB_NAME="${DB_NAME}" \
    -e DB_LOG_BIN_BASENAME="${DB_LOG_BIN_BASENAME:-mysql-bin}" \
    -e PITR_TARGET_DATETIME="${PITR_TARGET_DATETIME}" \
    -e PITR_START_FILE="${start_file}" \
    -e PITR_START_POS="${start_pos}" \
    db sh -ec '
      set -eu
      command -v mariadb-binlog >/dev/null 2>&1 || { echo "mariadb-binlog not found" >&2; exit 1; }

      all_files="$(ls -1 /tmp/koha-pitr-binlogs/${DB_LOG_BIN_BASENAME}.[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort)"
      [ -n "${all_files}" ] || { echo "No binlog files found for PITR" >&2; exit 1; }

      selected="${all_files}"
      if [ -n "${PITR_START_FILE}" ] && [ -f "/tmp/koha-pitr-binlogs/${PITR_START_FILE}" ]; then
        selected=""
        start_path="/tmp/koha-pitr-binlogs/${PITR_START_FILE}"
        while IFS= read -r binlog_file; do
          [ -n "${binlog_file}" ] || continue
          if [ "${binlog_file}" \< "${start_path}" ]; then
            continue
          fi
          selected="${selected}${selected:+ }${binlog_file}"
        done <<EOF
${all_files}
EOF
      fi

      [ -n "${selected}" ] || { echo "No binlogs selected for PITR" >&2; exit 1; }

      cmd="mariadb-binlog --stop-datetime=\"${PITR_TARGET_DATETIME}\""
      if [ -n "${PITR_START_POS}" ]; then
        cmd="${cmd} --start-position=${PITR_START_POS}"
      fi

      # shellcheck disable=SC2086
      eval "${cmd} ${selected}" | mariadb -uroot -p"${DB_ROOT_PASS}" "${DB_NAME}"
    '

  docker compose exec -T db sh -ec 'rm -rf /tmp/koha-pitr-binlogs'
  rm -rf "${pitr_tmp}"
  trap - RETURN

  log "PITR applied up to: ${PITR_TARGET_DATETIME}"
}

verify_restore() {
  local biblio_count="0"
  local es_count="0"

  biblio_count="$(docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" -e DB_NAME="${DB_NAME}" db sh -ec '
    mariadb -uroot -p"${DB_ROOT_PASS}" -N -e "SELECT COUNT(*) FROM ${DB_NAME}.biblio;"
  ' | tr -d '\r' | tail -n1)"

  if is_true "${USE_ELASTICSEARCH:-true}"; then
    es_count="$(docker compose exec -T es sh -ec '
      curl -fsS http://localhost:9200/koha_library_biblios/_count 2>/dev/null | sed -n "s/.*\"count\":\([0-9]*\).*/\1/p"
    ' | tail -n1 || true)"
  fi

  log "Verify: biblio_count=${biblio_count}, es_biblios_count=${es_count:-n/a}"
}

main() {
  for arg in "$@"; do
    case "${arg}" in
      --help|-h)
        usage
        exit 0
        ;;
    esac
  done

  load_env "$@"

  RESTORE_SOURCE_DIR="${RESTORE_SOURCE_DIR:-}"
  RESTORE_ES_DATA="${RESTORE_ES_DATA:-false}"
  RESTORE_LOGS="${RESTORE_LOGS:-false}"
  RESTORE_REINDEX="${RESTORE_REINDEX:-true}"
  RESTORE_VERIFY="${RESTORE_VERIFY:-true}"
  DRY_RUN="false"
  ASSUME_YES="${ASSUME_YES:-false}"
  PITR_TARGET_DATETIME="${PITR_TARGET_DATETIME:-}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --source) RESTORE_SOURCE_DIR="$2"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --pitr-datetime) PITR_TARGET_DATETIME="$2"; shift 2 ;;
      --restore-es-data) RESTORE_ES_DATA="true"; shift ;;
      --restore-logs) RESTORE_LOGS="true"; shift ;;
      --skip-reindex) RESTORE_REINDEX="false"; shift ;;
      --no-verify) RESTORE_VERIFY="false"; shift ;;
      --yes) ASSUME_YES="true"; shift ;;
      --env)
        shift
        [ "$#" -gt 0 ] || die "--env requires value"
        shift
        ;;
      --env=*) shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ -n "${RESTORE_SOURCE_DIR}" ] || die "RESTORE_SOURCE_DIR is empty (use --source or env.${AUTONOMOUS_ENVIRONMENT}.enc)"

  VOL_DB_PATH="${VOL_DB_PATH:?VOL_DB_PATH is required}"
  VOL_KOHA_CONF="${VOL_KOHA_CONF:?VOL_KOHA_CONF is required}"
  VOL_KOHA_DATA="${VOL_KOHA_DATA:?VOL_KOHA_DATA is required}"
  VOL_KOHA_LOGS="${VOL_KOHA_LOGS:?VOL_KOHA_LOGS is required}"
  VOL_ES_PATH="${VOL_ES_PATH:?VOL_ES_PATH is required}"
  KOHA_INSTANCE="${KOHA_INSTANCE:-library}"
  KOHA_CONF_UID="${KOHA_CONF_UID:-0}"
  KOHA_CONF_GID="${KOHA_CONF_GID:-1000}"

  verify_backup_set

  if is_true "${DRY_RUN}"; then
    log "DRY-RUN OK"
    log "Source: ${RESTORE_SOURCE_DIR}"
    log "SQL: ${SQL_DUMP_FILE}"
    log "Restore config/data: yes"
    log "Restore logs: ${RESTORE_LOGS}"
    log "Restore ES raw data: ${RESTORE_ES_DATA}"
    log "PITR target datetime: ${PITR_TARGET_DATETIME:-<none>}"
    log "Reindex ES after restore: ${RESTORE_REINDEX}"
    log "Post-restore verify: ${RESTORE_VERIFY}"
    exit 0
  fi

  log "Restore source: ${RESTORE_SOURCE_DIR}"
  log "Mode: ES_DATA=${RESTORE_ES_DATA}, LOGS=${RESTORE_LOGS}, REINDEX=${RESTORE_REINDEX}, VERIFY=${RESTORE_VERIFY}"
  [ -z "${PITR_TARGET_DATETIME}" ] || log "PITR target datetime: ${PITR_TARGET_DATETIME}"

  if ! is_true "${ASSUME_YES}"; then
    log "Starting restore in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
  fi

  log "[1/9] Stop stack"
  docker compose down --remove-orphans

  log "[2/9] Restore config/data archives"
  restore_archive_to_path "${RESTORE_SOURCE_DIR}/koha_config.tar.gz" "${VOL_KOHA_CONF}" "${KOHA_CONF_UID}" "${KOHA_CONF_GID}"
  restore_archive_to_path "${RESTORE_SOURCE_DIR}/koha_data.tar.gz" "${VOL_KOHA_DATA}" 1000 1000

  if is_true "${RESTORE_LOGS}"; then
    restore_archive_to_path "${RESTORE_SOURCE_DIR}/koha_logs.tar.gz" "${VOL_KOHA_LOGS}" 1000 1000
  fi

  normalize_koha_conf_permissions
  normalize_koha_conf_memcached

  log "[3/9] Prepare DB volume"
  wipe_bind_path "${VOL_DB_PATH}"

  log "[4/9] Prepare Elasticsearch volume"
  if is_true "${RESTORE_ES_DATA}" && [ -f "${RESTORE_SOURCE_DIR}/es_data.tar.gz" ]; then
    restore_archive_to_path "${RESTORE_SOURCE_DIR}/es_data.tar.gz" "${VOL_ES_PATH}" 1000 1000
  else
    wipe_bind_path "${VOL_ES_PATH}"
    docker run --rm -v "${VOL_ES_PATH}:/target" alpine sh -ec 'chown -R 1000:1000 /target'
  fi

  log "[5/9] Start DB"
  docker compose up -d db
  wait_service_healthy db 240

  log "[6/9] Import SQL"
  import_sql_dump

  if [ -n "${PITR_TARGET_DATETIME}" ]; then
    log "[7/9] Apply PITR"
    apply_pitr
  else
    log "[7/9] PITR skipped"
  fi

  log "[8/9] Start infra + koha"
  docker compose up -d es rabbitmq memcached
  wait_service_healthy es 300
  wait_service_healthy rabbitmq 240

  docker compose up -d koha
  wait_service_healthy koha 360

  normalize_koha_conf_memcached

  log "[9/9] Reindex + verify"
  if is_true "${RESTORE_REINDEX}" && is_true "${USE_ELASTICSEARCH:-true}"; then
    docker compose exec -T koha koha-elasticsearch --rebuild -v "${KOHA_INSTANCE}"
  fi

  if is_true "${RESTORE_VERIFY}"; then
    verify_restore
  fi

  log "Restore completed successfully"
}

main "$@"
