#!/usr/bin/env bash
# Script Purpose: Create full Koha backup set (DB + volumes + PITR artifacts) with integrity metadata.
# Usage: Run on host: ./scripts/backup.sh [options]. See --help for backup scope/retention flags.
set -euo pipefail
umask 027

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"

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
  [ -f "${ENV_FILE}" ] || die ".env not found: ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
}

require_vars() {
  local missing=0
  for v in DB_NAME DB_USER DB_PASS DB_ROOT_PASS VOL_DB_PATH VOL_KOHA_CONF VOL_KOHA_DATA; do
    if [ -z "${!v:-}" ]; then
      warn "Required var is empty: ${v}"
      missing=1
    fi
  done
  [ "${missing}" -eq 0 ] || die "Missing required environment variables"
}

safe_mkdir() {
  local path="$1"
  mkdir -p "${path}"
  touch "${path}/.write_test" || die "Backup path is not writable: ${path}"
  rm -f "${path}/.write_test"
}

should_exclude_offsite_file() {
  local filename="$1"
  local pattern
  local csv="${BACKUP_OFFSITE_EXCLUDE_FILES:-koha_data.tar.gz}"

  IFS=',' read -r -a OFFSITE_EXCLUDE_PATTERNS <<< "${csv}"
  for pattern in "${OFFSITE_EXCLUDE_PATTERNS[@]}"; do
    [ -n "${pattern}" ] || continue
    if [[ "${filename}" == ${pattern} ]]; then
      return 0
    fi
  done
  return 1
}

archive_bind_path() {
  local src="$1"
  local out="$2"

  if [ ! -d "${src}" ]; then
    warn "Bind path missing, skip: ${src}"
    return 0
  fi

  docker run --rm \
    -e ARCHIVE_NAME="${out}" \
    -v "${src}:/volume:ro" \
    -v "${WORK_DIR}:/backup" \
    alpine sh -ec '
      set -eu
      tar -czf "/backup/${ARCHIVE_NAME}" -C /volume .
    '
}

collect_master_status() {
  docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" db sh -ec '
    mariadb -uroot -p"${DB_ROOT_PASS}" -N -e "SHOW MASTER STATUS\\G"
  ' >"${WORK_DIR}/pitr_master_status.txt" || true

  local file pos
  file="$(awk -F': ' '/^File:/{print $2; exit}' "${WORK_DIR}/pitr_master_status.txt" || true)"
  pos="$(awk -F': ' '/^Position:/{print $2; exit}' "${WORK_DIR}/pitr_master_status.txt" || true)"

  {
    echo "PITR_START_FILE=${file}"
    echo "PITR_START_POS=${pos}"
  } >"${WORK_DIR}/pitr_master_status.env"

  docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" db sh -ec '
    mariadb -uroot -p"${DB_ROOT_PASS}" -N -e "SHOW VARIABLES LIKE \"log_bin\"; SHOW VARIABLES LIKE \"log_bin_basename\"; SHOW VARIABLES LIKE \"log_bin_index\"; SHOW VARIABLES LIKE \"binlog_format\"; SHOW VARIABLES LIKE \"server_id\";"
  ' >"${WORK_DIR}/mariadb_binlog_variables.txt" || true
}

archive_binlogs() {
  local base="${DB_LOG_BIN_BASENAME:-mysql-bin}"

  if [ ! -d "${VOL_DB_PATH}" ]; then
    warn "DB bind path missing, skip binlogs archive: ${VOL_DB_PATH}"
    return 0
  fi

  docker run --rm \
    -e BINLOG_BASE="${base}" \
    -v "${VOL_DB_PATH}:/volume:ro" \
    -v "${WORK_DIR}:/backup" \
    alpine sh -ec '
      set -eu
      if ls "/volume/${BINLOG_BASE}."[0-9][0-9][0-9][0-9][0-9][0-9] >/dev/null 2>&1; then
        files="$(ls -1 "/volume/${BINLOG_BASE}."[0-9][0-9][0-9][0-9][0-9][0-9] | xargs -n1 basename)"
        if [ -f "/volume/${BINLOG_BASE}.index" ]; then
          tar -czf /backup/mariadb_binlogs.tar.gz -C /volume "${BINLOG_BASE}.index" ${files}
        else
          tar -czf /backup/mariadb_binlogs.tar.gz -C /volume ${files}
        fi
      else
        echo "no-binlogs" >/backup/mariadb_binlogs.missing
      fi
    '
}

verify_backup_artifacts() {
  local f
  for f in "${WORK_DIR}"/*.sql.gz "${WORK_DIR}"/*.tar.gz; do
    [ -e "${f}" ] || continue
    gzip -t "${f}" >/dev/null
    case "${f}" in
      *.tar.gz) tar -tzf "${f}" >/dev/null ;;
    esac
  done

  (
    cd "${WORK_DIR}"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 \
      | sort -z \
      | xargs -0 -r sha256sum > SHA256SUMS
    sha256sum -c SHA256SUMS >/dev/null
  )
}

write_metadata() {
  cat >"${WORK_DIR}/backup_metadata.env" <<META
BACKUP_TIMESTAMP=${TS}
BACKUP_HOST=$(hostname)
BACKUP_ROOT=${BACKUP_ROOT}
BACKUP_OFFSITE_PATH=${BACKUP_OFFSITE_PATH}
BACKUP_OFFSITE_EXCLUDE_FILES=${BACKUP_OFFSITE_EXCLUDE_FILES}
DB_NAME=${DB_NAME}
KOHA_INSTANCE=${KOHA_INSTANCE:-library}
BACKUP_INCLUDE_LOGS=${BACKUP_INCLUDE_LOGS}
BACKUP_INCLUDE_ES_DATA=${BACKUP_INCLUDE_ES_DATA}
BACKUP_TOOL_VERSION=2
META

  {
    echo "File\tSizeBytes"
    find "${WORK_DIR}" -maxdepth 1 -type f -printf "%f\t%s\n" | sort
  } >"${WORK_DIR}/backup_manifest.tsv"
}

copy_lightweight_offsite() {
  local offsite_root="${BACKUP_OFFSITE_PATH:-}"
  local offsite_dir src base

  if [ -z "${offsite_root}" ]; then
    log "Offsite lightweight copy skipped (BACKUP_OFFSITE_PATH is empty)"
    return 0
  fi

  safe_mkdir "${offsite_root}"
  offsite_dir="${offsite_root%/}/${TS}"
  [ ! -e "${offsite_dir}" ] || die "Offsite backup dir already exists: ${offsite_dir}"
  mkdir -p "${offsite_dir}"

  for src in "${FINAL_DIR}"/*; do
    [ -e "${src}" ] || continue
    base="$(basename "${src}")"
    if should_exclude_offsite_file "${base}"; then
      log "Offsite exclude: ${base}"
      continue
    fi
    cp -a "${src}" "${offsite_dir}/${base}"
  done

  log "Offsite lightweight copy completed: ${offsite_dir}"
}

apply_retention() {
  local target_root="$1"

  [ -n "${target_root}" ] || return 0
  [ -d "${target_root}" ] || return 0

  if ! [[ "${BACKUP_RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    warn "BACKUP_RETENTION_DAYS is not numeric (${BACKUP_RETENTION_DAYS}), retention skipped"
    return 0
  fi

  if [ "${BACKUP_RETENTION_DAYS}" -eq 0 ]; then
    warn "BACKUP_RETENTION_DAYS=0, retention disabled"
    return 0
  fi

  find "${target_root}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +"${BACKUP_RETENTION_DAYS}" -print -exec rm -rf {} + || true
}

main() {
  load_env
  require_vars

  BACKUP_ROOT="${BACKUP_PATH:-${PROJECT_ROOT}/backups}"
  BACKUP_OFFSITE_PATH="${BACKUP_OFFSITE_PATH:-}"
  BACKUP_OFFSITE_EXCLUDE_FILES="${BACKUP_OFFSITE_EXCLUDE_FILES:-koha_data.tar.gz}"
  BACKUP_TMP_ROOT="${BACKUP_TMP_ROOT:-/tmp}"
  BACKUP_INCLUDE_LOGS="${BACKUP_INCLUDE_LOGS:-true}"
  BACKUP_INCLUDE_ES_DATA="${BACKUP_INCLUDE_ES_DATA:-false}"
  BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

  TS="$(date -u +'%Y-%m-%d_%H-%M-%S')"
  FINAL_DIR="${BACKUP_ROOT}/${TS}"
  WORK_DIR="$(mktemp -d "${BACKUP_TMP_ROOT%/}/koha-backup-${TS}-XXXXXX")"
  trap 'rm -rf "${WORK_DIR}"' ERR INT TERM

  safe_mkdir "${BACKUP_ROOT}"
  [ ! -e "${FINAL_DIR}" ] || die "Backup dir already exists: ${FINAL_DIR}"

  log "Backup staging dir: ${WORK_DIR}"
  log "Backup destination: ${FINAL_DIR}"

  log "[1/7] Dump MariaDB (${DB_NAME})"
  docker compose exec -T -e DB_ROOT_PASS="${DB_ROOT_PASS}" -e DB_NAME="${DB_NAME}" db sh -ec '
    if command -v mariadb-dump >/dev/null 2>&1; then
      DUMP_BIN=mariadb-dump
    else
      DUMP_BIN=mysqldump
    fi
    "$DUMP_BIN" --single-transaction --quick --routines --events --triggers --hex-blob --default-character-set=utf8mb4 -uroot -p"${DB_ROOT_PASS}" "${DB_NAME}"
  ' >"${WORK_DIR}/${DB_NAME}.sql"
  [ -s "${WORK_DIR}/${DB_NAME}.sql" ] || die "SQL dump is empty"
  gzip -9 "${WORK_DIR}/${DB_NAME}.sql"

  log "[2/7] Collect PITR metadata"
  collect_master_status

  log "[3/7] Archive database binlogs"
  archive_binlogs

  log "[4/7] Archive Koha config/data"
  archive_bind_path "${VOL_KOHA_CONF}" "koha_config.tar.gz"
  archive_bind_path "${VOL_KOHA_DATA}" "koha_data.tar.gz"

  log "[5/7] Archive logs (optional)"
  if is_true "${BACKUP_INCLUDE_LOGS}"; then
    archive_bind_path "${VOL_KOHA_LOGS:-}" "koha_logs.tar.gz"
  else
    log "Logs archive skipped (BACKUP_INCLUDE_LOGS=${BACKUP_INCLUDE_LOGS})"
  fi

  log "[6/7] Archive Elasticsearch data (optional)"
  if is_true "${BACKUP_INCLUDE_ES_DATA}"; then
    archive_bind_path "${VOL_ES_PATH:-}" "es_data.tar.gz"
  else
    log "ES data archive skipped (BACKUP_INCLUDE_ES_DATA=${BACKUP_INCLUDE_ES_DATA})"
  fi

  log "[7/7] Verify artifacts, checksums, metadata"
  verify_backup_artifacts
  write_metadata

  mv "${WORK_DIR}" "${FINAL_DIR}"
  WORK_DIR=""

  # normalize ownership to current user
  docker run --rm -e UID="$(id -u)" -e GID="$(id -g)" -v "${FINAL_DIR}:/data" alpine sh -ec 'chown -R "$UID:$GID" /data' || true

  copy_lightweight_offsite
  apply_retention "${BACKUP_ROOT}"
  apply_retention "${BACKUP_OFFSITE_PATH:-}"

  log "Backup completed: ${FINAL_DIR}"
  ls -lh "${FINAL_DIR}"
}

main "$@"
