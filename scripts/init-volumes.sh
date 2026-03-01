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

set -euo pipefail

FIX_EXISTING=false
case "${1:-}" in
  "")
    ;;
  --fix-existing)
    FIX_EXISTING=true
    ;;
  *)
    echo "Usage: $0 [--fix-existing]" >&2
    exit 1
    ;;
esac

# --- 1) Load .env (robust) ---
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Error: .env file not found at: $ENV_FILE" >&2
  exit 1
fi

echo "🌍 Loading environment variables from .env..."
while IFS='=' read -r key value; do
  [[ "$key" =~ ^\s*# ]] && continue
  [[ -z "${key//[[:space:]]/}" ]] && continue

  # trim ключ
  key=$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # значення: trim + strip quotes
  value=$(echo "${value:-}" | sed \
    -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    -e 's/^"//' -e 's/"$//' \
    -e "s/^'//" -e "s/'$//")

  export "$key=$value"
done < <(grep -vE '^\s*#' "$ENV_FILE" | grep -vE '^\s*$')

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

# --- 4) Privileged runner helper ---
if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo "❌ sudo is required to manage paths like /srv. Run as root or install sudo." >&2
  exit 1
fi

run() {
  "${SUDO[@]}" "$@"
}

# --- 5) Create directories ---
echo "==> Creating volume directories..."
run mkdir -p "$VOL_DB_PATH" "$VOL_KOHA_CONF" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
if ! $SKIP_ES; then
  run mkdir -p "$VOL_ES_PATH"
fi

# --- 6) Set ownership + baseline permissions ---
echo "==> Setting ownership + baseline permissions..."

echo " -> MariaDB (${DB_UID}:${DB_GID})"
run chown -R "${DB_UID}:${DB_GID}" "$VOL_DB_PATH"
run chmod 750 "$VOL_DB_PATH"

if ! $SKIP_ES; then
  echo " -> Elasticsearch (${ES_UID}:${ES_GID})"
  run chown -R "${ES_UID}:${ES_GID}" "$VOL_ES_PATH"
  run chmod 775 "$VOL_ES_PATH"
fi

echo " -> Koha config (${KOHA_CONF_UID}:${KOHA_CONF_GID})"
run chown -R "${KOHA_CONF_UID}:${KOHA_CONF_GID}" "$VOL_KOHA_CONF"
run chmod 2775 "$VOL_KOHA_CONF"

echo " -> Koha data/logs (${KOHA_UID}:${KOHA_GID})"
run chown -R "${KOHA_UID}:${KOHA_GID}" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
run chmod 775 "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"

# --- 6) Optional: fix existing perms (remove 777 etc.) ---
if $FIX_EXISTING; then
  echo "==> --fix-existing enabled: normalizing permissions inside volumes."

  echo " -> Fixing MariaDB modes (dirs=750, files=640)"
  run find "$VOL_DB_PATH" -type d -exec chmod 750 {} +
  run find "$VOL_DB_PATH" -type f -exec chmod 640 {} +

  if ! $SKIP_ES; then
    echo " -> Fixing Elasticsearch modes (dirs=775, files=664)"
    run find "$VOL_ES_PATH" -type d -exec chmod 775 {} +
    run find "$VOL_ES_PATH" -type f -exec chmod 664 {} +
  fi

  echo " -> Fixing Koha config modes (dirs=2775, files=640)"
  run find "$VOL_KOHA_CONF" -type d -exec chmod 2775 {} +
  run find "$VOL_KOHA_CONF" -type f -exec chmod 640 {} +

  echo " -> Fixing Koha data/logs modes (dirs=775, files=664)"
  run find "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS" -type d -exec chmod 775 {} +
  run find "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS" -type f -exec chmod 664 {} +
fi

echo "==> Done! Volumes are ready."
if $SKIP_ES; then
  ls -ld "$VOL_DB_PATH" "$VOL_KOHA_CONF" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
else
  ls -ld "$VOL_DB_PATH" "$VOL_ES_PATH" "$VOL_KOHA_CONF" "$VOL_KOHA_DATA" "$VOL_KOHA_LOGS"
fi
