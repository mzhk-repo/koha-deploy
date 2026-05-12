#!/usr/bin/env bash
# Script Purpose: Smoke-test Koha SQL backup restore in a temporary MariaDB container.
# Usage: Run on host: ./scripts/test-restore.sh [--env dev|prod] [--dry-run] [backup-dir].
set -euo pipefail
umask 027

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/autonomous-env.sh"

ENVIRONMENT_ARG=""
DRY_RUN="false"
BACKUP_SOURCE=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/test-restore.sh [options] [backup-dir]

Options:
  --source DIR                 Backup directory to test (same as positional backup-dir)
  --dry-run                    Print checks only; do not restore and do not update metrics
  --env dev|prod               Environment to decrypt (default: SERVER_ENV)
  --help                       Show this help

Smoke restore imports Koha SQL dump into a temporary MariaDB container and does not touch production Koha DB.
USAGE
}

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

read_env_or_default() {
  local key="$1"
  local default_value="$2"
  local env_value="${!key:-}"

  if [ -n "${env_value}" ]; then
    printf '%s\n' "${env_value}"
    return 0
  fi

  printf '%s\n' "${default_value}"
}

abs_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${PROJECT_ROOT}" "${path}"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      shift
      [ "$#" -gt 0 ] || die "--source requires value"
      BACKUP_SOURCE="$1"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --env)
      shift
      [ "$#" -gt 0 ] || die "--env requires value"
      ENVIRONMENT_ARG="$1"
      ;;
    --env=*)
      ENVIRONMENT_ARG="${1#--env=}"
      ;;
    dev|development|prod|production)
      ENVIRONMENT_ARG="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "${BACKUP_SOURCE}" ]; then
        BACKUP_SOURCE="$1"
      else
        die "Unknown option: $1"
      fi
      ;;
  esac
  shift
done

load_autonomous_env "${PROJECT_ROOT}" "${ENVIRONMENT_ARG}"
cd "${PROJECT_ROOT}"

require_command docker
require_command find
require_command mktemp

DB_NAME="$(read_env_or_default DB_NAME koha_library)"
BACKUP_ROOT="$(read_env_or_default BACKUP_PATH "${PROJECT_ROOT}/backups")"
MARIADB_IMAGE="$(read_env_or_default MARIADB_IMAGE "docker.io/mariadb:11")"
NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "/data/node-exporter-textfile")"
RESTORE_SMOKE_METRICS_FILE="$(read_env_or_default RESTORE_SMOKE_METRICS_FILE "koha_restore_smoke.prom")"
RESTORE_SMOKE_ENV_LABEL="$(read_env_or_default RESTORE_SMOKE_ENV_LABEL "prod")"
RESTORE_SMOKE_SERVICE_LABEL="$(read_env_or_default RESTORE_SMOKE_SERVICE_LABEL "koha")"
RESTORE_SMOKE_TIMEOUT_SECONDS="$(read_env_or_default RESTORE_SMOKE_TIMEOUT_SECONDS "90")"

if ! [[ "${RESTORE_SMOKE_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [ "${RESTORE_SMOKE_TIMEOUT_SECONDS}" -lt 10 ]; then
  die "RESTORE_SMOKE_TIMEOUT_SECONDS must be an integer >= 10"
fi

BACKUP_ROOT_ABS="$(abs_path "${BACKUP_ROOT}")"
if [ -n "${BACKUP_SOURCE}" ]; then
  BACKUP_SOURCE="$(abs_path "${BACKUP_SOURCE}")"
else
  BACKUP_SOURCE="$(
    find "${BACKUP_ROOT_ABS}" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr \
      | head -n1 \
      | awk '{print $2}' || true
  )"
fi

[ -n "${BACKUP_SOURCE}" ] || die "Backup directory not found. Pass --source or create a backup in ${BACKUP_ROOT_ABS}"
[ -d "${BACKUP_SOURCE}" ] || die "Backup directory not found: ${BACKUP_SOURCE}"

SQL_DUMP_FILE=""
if [ -f "${BACKUP_SOURCE}/${DB_NAME}.sql.gz" ]; then
  SQL_DUMP_FILE="${BACKUP_SOURCE}/${DB_NAME}.sql.gz"
elif [ -f "${BACKUP_SOURCE}/${DB_NAME}.sql" ]; then
  SQL_DUMP_FILE="${BACKUP_SOURCE}/${DB_NAME}.sql"
else
  SQL_DUMP_FILE="$(find "${BACKUP_SOURCE}" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.sql' \) | sort | head -n1 || true)"
fi

[ -n "${SQL_DUMP_FILE}" ] || die "SQL dump not found in backup directory: ${BACKUP_SOURCE}"

run_timestamp="$(date +%s)"
success_timestamp="0"
restore_status="0"
emit_metrics_on_exit="1"
tmp_dir="$(mktemp -d /tmp/koha-restore-smoke-XXXXXX)"
container_name="koha-restore-smoke-$(date +%s)"
smoke_db_name="koha_restore_smoke"
smoke_root_password="koha_restore_smoke_pass"

if [ "${DRY_RUN}" = "true" ]; then
  emit_metrics_on_exit="0"
fi

ensure_metrics_dir() {
  local dir="$1"

  if mkdir -p "${dir}" >/dev/null 2>&1; then
    return 0
  fi

  local parent_dir
  local base_name
  parent_dir="$(dirname "${dir}")"
  base_name="$(basename "${dir}")"

  if [ ! -d "${parent_dir}" ]; then
    warn "Metrics parent directory does not exist: ${parent_dir}"
    return 1
  fi

  docker run --rm \
    -v "${parent_dir}:/parent" \
    alpine:3.20 \
    sh -c "mkdir -p '/parent/${base_name}'" >/dev/null
}

emit_restore_metrics() {
  ensure_metrics_dir "${NODE_EXPORTER_TEXTFILE_DIR}" || {
    warn "Failed to prepare metrics dir: ${NODE_EXPORTER_TEXTFILE_DIR}"
    return 0
  }

  local metrics_payload
  metrics_payload="$(cat <<EOF
# HELP koha_restore_smoke_last_run_timestamp_seconds Unix timestamp of the last Koha restore smoke test attempt.
# TYPE koha_restore_smoke_last_run_timestamp_seconds gauge
koha_restore_smoke_last_run_timestamp_seconds{env="${RESTORE_SMOKE_ENV_LABEL}",service="${RESTORE_SMOKE_SERVICE_LABEL}"} ${run_timestamp}
# HELP koha_restore_smoke_last_success_timestamp_seconds Unix timestamp of the last successful Koha restore smoke test.
# TYPE koha_restore_smoke_last_success_timestamp_seconds gauge
koha_restore_smoke_last_success_timestamp_seconds{env="${RESTORE_SMOKE_ENV_LABEL}",service="${RESTORE_SMOKE_SERVICE_LABEL}"} ${success_timestamp}
# HELP koha_restore_smoke_last_status Last Koha restore smoke test status (1=success, 0=failure).
# TYPE koha_restore_smoke_last_status gauge
koha_restore_smoke_last_status{env="${RESTORE_SMOKE_ENV_LABEL}",service="${RESTORE_SMOKE_SERVICE_LABEL}"} ${restore_status}
EOF
)"

  printf '%s\n' "${metrics_payload}" | docker run --rm -i \
    -v "${NODE_EXPORTER_TEXTFILE_DIR}:/metrics" \
    alpine:3.20 \
    sh -c "cat > /metrics/${RESTORE_SMOKE_METRICS_FILE}"
}

cleanup() {
  local exit_code=$?

  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  rm -rf "${tmp_dir}" >/dev/null 2>&1 || true

  if [ "${emit_metrics_on_exit}" = "1" ]; then
    emit_restore_metrics
  fi

  exit "${exit_code}"
}
trap cleanup EXIT

log "Restore smoke source: ${BACKUP_SOURCE}"
log "SQL dump: ${SQL_DUMP_FILE}"
log "Metrics file: ${NODE_EXPORTER_TEXTFILE_DIR}/${RESTORE_SMOKE_METRICS_FILE}"

if [ "${DRY_RUN}" = "true" ]; then
  log "DRY-RUN: restore smoke test and freshness metrics update are skipped"
  log "DRY-RUN: would start temporary MariaDB container and import ${SQL_DUMP_FILE}"
  exit 0
fi

if [ -f "${BACKUP_SOURCE}/SHA256SUMS" ]; then
  (cd "${BACKUP_SOURCE}" && sha256sum -c SHA256SUMS >/dev/null)
fi

if [[ "${SQL_DUMP_FILE}" == *.gz ]]; then
  require_command gzip
  gzip -t "${SQL_DUMP_FILE}"
else
  [ -s "${SQL_DUMP_FILE}" ] || die "SQL dump is empty: ${SQL_DUMP_FILE}"
fi

log "Starting temporary MariaDB container: ${container_name}"
docker run -d --name "${container_name}" \
  -e "MYSQL_ROOT_PASSWORD=${smoke_root_password}" \
  -e "MYSQL_DATABASE=${smoke_db_name}" \
  -v "${tmp_dir}:/var/lib/mysql" \
  "${MARIADB_IMAGE}" >/dev/null

max_attempts=$((RESTORE_SMOKE_TIMEOUT_SECONDS / 2))
for attempt in $(seq 1 "${max_attempts}"); do
  if docker exec "${container_name}" mariadb-admin ping -h127.0.0.1 -uroot -p"${smoke_root_password}" --silent >/dev/null 2>&1; then
    break
  fi
  if [ "${attempt}" -eq "${max_attempts}" ]; then
    docker logs "${container_name}" --tail 120 || true
    die "Temporary MariaDB did not become ready within ${RESTORE_SMOKE_TIMEOUT_SECONDS}s"
  fi
  sleep 2
done

log "Importing dump into temporary database: ${smoke_db_name}"
if [[ "${SQL_DUMP_FILE}" == *.gz ]]; then
  gzip -dc "${SQL_DUMP_FILE}" | docker exec -i "${container_name}" mariadb -uroot -p"${smoke_root_password}" "${smoke_db_name}"
else
  docker exec -i "${container_name}" mariadb -uroot -p"${smoke_root_password}" "${smoke_db_name}" < "${SQL_DUMP_FILE}"
fi

table_count="$(
  docker exec "${container_name}" mariadb -N -B -uroot -p"${smoke_root_password}" \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${smoke_db_name}';" \
    | tr -d '\r' \
    | tail -n1
)"

if ! [[ "${table_count}" =~ ^[0-9]+$ ]] || [ "${table_count}" -lt 1 ]; then
  die "Restore smoke sanity check failed (table count: ${table_count:-n/a})"
fi

restore_status="1"
success_timestamp="$(date +%s)"
log "Restore smoke completed successfully (tables in ${smoke_db_name}: ${table_count})"
