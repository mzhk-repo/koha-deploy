#!/usr/bin/env bash
# Script Purpose: Initialize required bind-mount directories and normalize permissions for Koha stack volumes.
# Usage: Run on host before first deploy or after storage reset: ./scripts/init-volumes.sh.
# Ініціалізує директорії bind-volume для Koha stack з .env та виставляє права.
# Підтримувані volume-path змінні:
# - VOL_DB_PATH        -> /var/lib/mysql
# - VOL_ES_PATH        -> /usr/share/elasticsearch/data
# - VOL_KOHA_CONF      -> /etc/koha/sites
# - VOL_KOHA_DATA      -> /var/lib/koha
# - VOL_KOHA_LOGS      -> /var/log/koha
#
# Використання:
#   ./scripts/init-volumes.sh
#   ./scripts/init-volumes.sh --fix-existing  # рекурсивно вирівняти права у вже існуючих даних
#   ORCHESTRATOR_ENV_FILE=/tmp/env.decrypted ./scripts/init-volumes.sh

set -euo pipefail

FIX_EXISTING=false
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-}"

usage() {
  echo "Usage: $0 [--fix-existing] [--env-file FILE]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix-existing)
      FIX_EXISTING=true
      ;;
    --env-file)
      shift
      [[ $# -gt 0 ]] || { usage; exit 1; }
      ENV_FILE="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/orchestrator-env.sh"
ENV_FILE="$(resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}")"
echo "🌍 Loading environment variables from ${ENV_FILE}..."
load_orchestrator_env_file "${ENV_FILE}"

# --- 2) Validate required paths (SSOT) ---
: "${VOL_DB_PATH:?VOL_DB_PATH is required in .env}"
: "${VOL_ES_PATH:?VOL_ES_PATH is required in .env}"
: "${VOL_KOHA_CONF:?VOL_KOHA_CONF is required in .env}"
: "${VOL_KOHA_DATA:?VOL_KOHA_DATA is required in .env}"
: "${VOL_KOHA_LOGS:?VOL_KOHA_LOGS is required in .env}"

# --- 3) UID/GID mapping (overrideable via .env) ---
# MariaDB офіційно зазвичай mysql (999:999) у Debian-based образах.
# Elasticsearch офіційний image: user 1000.
# Koha у цьому репо створює runtime user KOHA_INSTANCE-koha з UID/GID 1000.
DB_UID="${DB_UID:-999}"
DB_GID="${DB_GID:-999}"
ES_UID="${ES_UID:-1000}"
ES_GID="${ES_GID:-1000}"
KOHA_UID="${KOHA_UID:-1000}"
KOHA_GID="${KOHA_GID:-1000}"
KOHA_CONF_UID="${KOHA_CONF_UID:-0}"
KOHA_CONF_GID="${KOHA_CONF_GID:-1000}"

if [[ "${USE_ELASTICSEARCH:-true}" =~ ^([Ff][Aa][Ll][Ss][Ee]|0|no|NO)$ ]]; then
  SKIP_ES=true
else
  SKIP_ES=false
fi

# --- 4) Normalize + guard paths ---
abspath() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(pwd)/$path"
  fi
}

guard_path() {
  local path="$1"
  if [[ -z "$path" || "$path" == "/" || "$path" == "." || "$path" == ".." ]]; then
    echo "❌ Error: unsafe path: $path" >&2
    exit 1
  fi
}

VOL_DB_PATH="$(abspath "$VOL_DB_PATH")"
VOL_KOHA_CONF="$(abspath "$VOL_KOHA_CONF")"
VOL_KOHA_DATA="$(abspath "$VOL_KOHA_DATA")"
VOL_KOHA_LOGS="$(abspath "$VOL_KOHA_LOGS")"
if ! $SKIP_ES; then
  VOL_ES_PATH="$(abspath "$VOL_ES_PATH")"
fi

guard_path "$VOL_DB_PATH"
guard_path "$VOL_KOHA_CONF"
guard_path "$VOL_KOHA_DATA"
guard_path "$VOL_KOHA_LOGS"
if ! $SKIP_ES; then
  guard_path "$VOL_ES_PATH"
fi

# --- 5) Privileged execution strategy ---
DOCKER_IMAGE="${INIT_VOLUMES_HELPER_IMAGE:-alpine:3.20}"
HAS_DOCKER=false
CAN_SUDO_NOPASS=false

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  HAS_DOCKER=true
fi

if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  CAN_SUDO_NOPASS=true
fi

if [[ "${EUID}" -eq 0 ]]; then
  PRIV_MODE="root"
elif $HAS_DOCKER; then
  PRIV_MODE="docker"
elif $CAN_SUDO_NOPASS; then
  PRIV_MODE="sudo"
else
  echo "❌ Need privileges for bind paths. Install Docker (recommended) or configure passwordless sudo." >&2
  exit 1
fi

mkdir_with_docker() {
  local dir_path="$1"
  local parent_dir
  local base_name
  parent_dir="$(dirname "$dir_path")"
  base_name="$(basename "$dir_path")"
  docker run --rm \
    -e BASE_NAME="$base_name" \
    -v "$parent_dir:/host-parent" \
    "$DOCKER_IMAGE" \
    sh -ceu 'mkdir -p "/host-parent/$BASE_NAME"'
}

chown_recursive_with_docker() {
  local owner="$1"
  local path="$2"
  docker run --rm \
    -e OWNER="$owner" \
    -v "$path:/target" \
    "$DOCKER_IMAGE" \
    sh -ceu 'chown -R "$OWNER" /target'
}

chmod_with_docker() {
  local mode="$1"
  local path="$2"
  docker run --rm \
    -e MODE="$mode" \
    -v "$path:/target" \
    "$DOCKER_IMAGE" \
    sh -ceu 'chmod "$MODE" /target'
}

fix_modes_with_docker() {
  local path="$1"
  local dir_mode="$2"
  local file_mode="$3"
  docker run --rm \
    -e DIR_MODE="$dir_mode" \
    -e FILE_MODE="$file_mode" \
    -v "$path:/target" \
    "$DOCKER_IMAGE" \
    sh -ceu 'find /target -type d -exec chmod "$DIR_MODE" {} \; && find /target -type f -exec chmod "$FILE_MODE" {} \;'
}

ensure_dir() {
  local dir_path="$1"
  if mkdir -p "$dir_path" 2>/dev/null; then
    return
  fi

  case "$PRIV_MODE" in
    root) mkdir -p "$dir_path" ;;
    sudo) sudo -n mkdir -p "$dir_path" ;;
    docker) mkdir_with_docker "$dir_path" ;;
  esac
}

chown_recursive() {
  local uid="$1"
  local gid="$2"
  local path="$3"
  local owner="${uid}:${gid}"
  case "$PRIV_MODE" in
    root) chown -R "$owner" "$path" ;;
    sudo) sudo -n chown -R "$owner" "$path" ;;
    docker) chown_recursive_with_docker "$owner" "$path" ;;
  esac
}

chmod_path() {
  local mode="$1"
  local path="$2"
  case "$PRIV_MODE" in
    root) chmod "$mode" "$path" ;;
    sudo) sudo -n chmod "$mode" "$path" ;;
    docker) chmod_with_docker "$mode" "$path" ;;
  esac
}

fix_modes_path() {
  local path="$1"
  local dir_mode="$2"
  local file_mode="$3"
  case "$PRIV_MODE" in
    root)
      find "$path" -type d -exec chmod "$dir_mode" {} \;
      find "$path" -type f -exec chmod "$file_mode" {} \;
      ;;
    sudo)
      sudo -n find "$path" -type d -exec chmod "$dir_mode" {} \;
      sudo -n find "$path" -type f -exec chmod "$file_mode" {} \;
      ;;
    docker)
      fix_modes_with_docker "$path" "$dir_mode" "$file_mode"
      ;;
  esac
}

case "$PRIV_MODE" in
  root) echo "==> Privileged mode: root" ;;
  sudo) echo "==> Privileged mode: passwordless sudo" ;;
  docker) echo "==> Privileged mode: Docker ephemeral helper (${DOCKER_IMAGE})" ;;
esac

# --- 6) Create directories ---
echo "==> Creating volume directories..."
ensure_dir "$VOL_DB_PATH"
ensure_dir "$VOL_KOHA_CONF"
ensure_dir "$VOL_KOHA_DATA"
ensure_dir "$VOL_KOHA_LOGS"
if ! $SKIP_ES; then
  ensure_dir "$VOL_ES_PATH"
fi

# --- 7) Set ownership + baseline permissions ---
echo "==> Setting ownership + baseline permissions..."

echo " -> MariaDB (${DB_UID}:${DB_GID})"
chown_recursive "$DB_UID" "$DB_GID" "$VOL_DB_PATH"
chmod_path 750 "$VOL_DB_PATH"

if ! $SKIP_ES; then
  echo " -> Elasticsearch (${ES_UID}:${ES_GID})"
  chown_recursive "$ES_UID" "$ES_GID" "$VOL_ES_PATH"
  chmod_path 775 "$VOL_ES_PATH"
fi

echo " -> Koha config (${KOHA_CONF_UID}:${KOHA_CONF_GID})"
chown_recursive "$KOHA_CONF_UID" "$KOHA_CONF_GID" "$VOL_KOHA_CONF"
chmod_path 2775 "$VOL_KOHA_CONF"

echo " -> Koha data/logs (${KOHA_UID}:${KOHA_GID})"
chown_recursive "$KOHA_UID" "$KOHA_GID" "$VOL_KOHA_DATA"
chown_recursive "$KOHA_UID" "$KOHA_GID" "$VOL_KOHA_LOGS"
chmod_path 775 "$VOL_KOHA_DATA"
chmod_path 775 "$VOL_KOHA_LOGS"

# --- 8) Optional: fix existing perms (remove 777 etc.) ---
if $FIX_EXISTING; then
  echo "==> --fix-existing enabled: normalizing permissions inside volumes."

  echo " -> Fixing MariaDB modes (dirs=750, files=640)"
  fix_modes_path "$VOL_DB_PATH" 750 640

  if ! $SKIP_ES; then
    echo " -> Fixing Elasticsearch modes (dirs=775, files=664)"
    fix_modes_path "$VOL_ES_PATH" 775 664
  fi

  echo " -> Fixing Koha config modes (dirs=2775, files=640)"
  fix_modes_path "$VOL_KOHA_CONF" 2775 640

  echo " -> Fixing Koha data/logs modes (dirs=775, files=664)"
  fix_modes_path "$VOL_KOHA_DATA" 775 664
  fix_modes_path "$VOL_KOHA_LOGS" 775 664
fi

echo "==> Done! Volumes are ready."
if $SKIP_ES; then
  ls -ld "$VOL_DB_PATH" "$VOL_KOHA_CONF" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
else
  ls -ld "$VOL_DB_PATH" "$VOL_ES_PATH" "$VOL_KOHA_CONF" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
fi
