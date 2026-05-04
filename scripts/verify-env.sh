#!/usr/bin/env bash
# Script Purpose: Validate dotenv syntax and key synchronization between .env.example and local .env.
# Usage: ./scripts/verify-env.sh [--env-file FILE] [--example-file FILE] [--example-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
EXAMPLE_FILE="${EXAMPLE_FILE:-${PROJECT_ROOT}/.env.example}"
EXAMPLE_ONLY="false"
COMPOSE_FILE="${COMPOSE_FILE:-${PROJECT_ROOT}/docker-compose.yaml}"

if [ ! -f "${COMPOSE_FILE}" ] && [ -f "${PROJECT_ROOT}/docker-compose.yml" ]; then
  COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
fi

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/verify-env.sh [options]

Options:
  --env-file FILE      Path to local env file (default: ./.env)
  --example-file FILE  Path to template env file (default: ./.env.example)
  --example-only       Validate only .env.example (skip local .env sync check)
  --help               Show help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || fail "--env-file requires value"
      ENV_FILE="$1"
      ;;
    --example-file)
      shift
      [ "$#" -gt 0 ] || fail "--example-file requires value"
      EXAMPLE_FILE="$1"
      ;;
    --example-only)
      EXAMPLE_ONLY="true"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

[ -f "${EXAMPLE_FILE}" ] || fail ".env.example file not found: ${EXAMPLE_FILE}"
[ -f "${COMPOSE_FILE}" ] || fail "Compose file not found: ${COMPOSE_FILE}"

if [ "${EXAMPLE_ONLY}" != "true" ] && [ ! -f "${ENV_FILE}" ]; then
  echo "WARNING: local env file not found, switching to --example-only mode: ${ENV_FILE}" >&2
  EXAMPLE_ONLY="true"
fi

parse_keys_strict() {
  local file="$1"
  local lineno=0
  local line key

  while IFS= read -r line || [ -n "${line}" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"

    if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    if [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      printf '%s\n' "${key}"
      continue
    fi

    fail "Invalid dotenv line in ${file}:${lineno}: ${line}"
  done < "${file}"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

example_keys_file="${tmp_dir}/example.keys"
parse_keys_strict "${EXAMPLE_FILE}" | sort -u > "${example_keys_file}"

compose_keys_file="${tmp_dir}/compose.keys"
grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' "${COMPOSE_FILE}" | sed 's/^..//' | sort -u > "${compose_keys_file}"

missing_compose_keys="${tmp_dir}/missing.compose.keys"
comm -23 "${compose_keys_file}" "${example_keys_file}" > "${missing_compose_keys}" || true
if [ -s "${missing_compose_keys}" ]; then
  echo "Missing compose keys in .env.example:" >&2
  cat "${missing_compose_keys}" >&2
  fail ".env.example does not include all keys used by docker-compose"
fi

ops_required_file="${tmp_dir}/ops-required.keys"
cat > "${ops_required_file}" <<'OPS'
BACKUP_PATH
BACKUP_RCLONE_REMOTE
BACKUP_RCLONE_FOLDER
BACKUP_OFFSITE_EXCLUDE_FILES
BACKUP_TMP_ROOT
BACKUP_RETENTION_DAYS
BACKUP_INCLUDE_LOGS
BACKUP_INCLUDE_ES_DATA
RESTORE_SOURCE_DIR
RESTORE_REINDEX
RESTORE_VERIFY
RESTORE_LOGS
RESTORE_ES_DATA
PITR_TARGET_DATETIME
LOG_EXPORT_ROOT
LOG_STATE_FILE
LOG_FIRST_SINCE
OPS
sort -u "${ops_required_file}" -o "${ops_required_file}"

missing_ops_keys="${tmp_dir}/missing.ops.keys"
comm -23 "${ops_required_file}" "${example_keys_file}" > "${missing_ops_keys}" || true
if [ -s "${missing_ops_keys}" ]; then
  echo "Missing operational keys in .env.example:" >&2
  cat "${missing_ops_keys}" >&2
  fail ".env.example is missing required keys for operational scripts"
fi

if [ "${EXAMPLE_ONLY}" != "true" ]; then
  env_keys_file="${tmp_dir}/env.keys"
  parse_keys_strict "${ENV_FILE}" | sort -u > "${env_keys_file}"

  missing_in_env="${tmp_dir}/missing.in.env"
  missing_in_example="${tmp_dir}/missing.in.example"

  comm -23 "${example_keys_file}" "${env_keys_file}" > "${missing_in_env}" || true
  comm -13 "${example_keys_file}" "${env_keys_file}" > "${missing_in_example}" || true

  if [ -s "${missing_in_env}" ]; then
    echo "Keys present in .env.example but missing in .env:" >&2
    cat "${missing_in_env}" >&2
    fail "Local .env is not synchronized with .env.example"
  fi

  if [ -s "${missing_in_example}" ]; then
    echo "Keys present in .env but missing in .env.example:" >&2
    cat "${missing_in_example}" >&2
    fail ".env.example is not synchronized with local .env"
  fi
fi

if ! docker compose --env-file "${EXAMPLE_FILE}" -f "${COMPOSE_FILE}" config >/dev/null; then
  fail "docker compose config failed with .env.example"
fi

if [ "${EXAMPLE_ONLY}" != "true" ]; then
  if ! docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null; then
    fail "docker compose config failed with .env"
  fi
fi

echo "OK: env validation passed."
