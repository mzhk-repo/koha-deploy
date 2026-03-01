#!/usr/bin/env bash
# Script Purpose: Install and enable systemd service/timer that periodically collects docker compose logs.
# Usage: sudo ./scripts/install-collect-logs-timer.sh [--interval 5min|10min|1h] [--no-start]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYSTEMD_DIR="${PROJECT_ROOT}/systemd"

SERVICE_NAME="koha-deploy-collect-logs.service"
TIMER_NAME="koha-deploy-collect-logs.timer"
SERVICE_SRC="${SYSTEMD_DIR}/${SERVICE_NAME}"
TIMER_SRC="${SYSTEMD_DIR}/${TIMER_NAME}"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}"
TIMER_DST="/etc/systemd/system/${TIMER_NAME}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: sudo ./scripts/install-collect-logs-timer.sh [options]

Options:
  --interval VALUE   Replace OnUnitActiveSec in timer (default from file is 5min)
  --no-start         Install and enable timer, but do not start immediately
  --help             Show help
USAGE
}

main() {
  local interval=""
  local no_start=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interval)
        shift
        [ "$#" -gt 0 ] || die "--interval requires value"
        interval="$1"
        ;;
      --no-start)
        no_start=true
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
    shift
  done

  [ -f "${SERVICE_SRC}" ] || die "Missing source file: ${SERVICE_SRC}"
  [ -f "${TIMER_SRC}" ] || die "Missing source file: ${TIMER_SRC}"

  install -m 0644 "${SERVICE_SRC}" "${SERVICE_DST}"
  if [ -n "${interval}" ]; then
    sed "s/^OnUnitActiveSec=.*/OnUnitActiveSec=${interval}/" "${TIMER_SRC}" > "${TIMER_DST}"
    chmod 0644 "${TIMER_DST}"
  else
    install -m 0644 "${TIMER_SRC}" "${TIMER_DST}"
  fi

  systemctl daemon-reload
  systemctl enable "${TIMER_NAME}"

  if ! ${no_start}; then
    systemctl restart "${TIMER_NAME}"
    systemctl start "${SERVICE_NAME}" || true
  fi

  log "Installed: ${SERVICE_DST}"
  log "Installed: ${TIMER_DST}"
  log "Enabled timer: ${TIMER_NAME}"
  systemctl list-timers --all --no-pager | grep -E "koha-deploy-collect-logs|NEXT|LEFT" || true
}

main "$@"
