#!/usr/bin/env bash
# Script Purpose: Orchestrate live Koha config patch modules for first bootstrap or targeted reruns.
# Usage: ./scripts/bootstrap-live-configs.sh [--all | --modules LIST | --module NAME] [--env-file FILE] [--wait-timeout SEC] [--dry-run] [--no-restart]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
WAIT_TIMEOUT=300
DRY_RUN=false
NO_RESTART=false
LIST_MODULES=false
USE_ALL=false

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap-live-configs.sh [options]

Module selection:
  --all                 Run all modules (default if none selected)
  --modules LIST        Comma-separated list: timezone,trusted-proxies,memcached,message-broker,smtp,domain-prefs,identity-provider,oidc-prefs,opac-matomo,csp-report-only,verify
  --module NAME         Repeatable module selector (same names as above)
  --list-modules        Print available modules and exit

Runtime options:
  --env-file FILE       Path to env file (default: ./.env)
  --wait-timeout SEC    Wait timeout for koha-conf.xml (default: 300)
  --dry-run             Run modules in dry-run mode
  --no-restart          Do not restart koha after patch modules
  --help                Show help

Examples:
  ./scripts/bootstrap-live-configs.sh --all
  ./scripts/bootstrap-live-configs.sh --modules smtp,verify
  ./scripts/bootstrap-live-configs.sh --module timezone --module memcached
USAGE
}

MODULE_ORDER=(timezone trusted-proxies memcached message-broker smtp domain-prefs identity-provider oidc-prefs opac-matomo csp-report-only verify)
declare -A MODULE_SCRIPT=(
  [timezone]="patch-koha-conf-xml-timezone.sh"
  [trusted-proxies]="patch-koha-conf-xml-trusted-proxies.sh"
  [memcached]="patch-koha-conf-xml-memcached.sh"
  [message-broker]="patch-koha-conf-xml-message-broker.sh"
  [smtp]="patch-koha-conf-xml-smtp.sh"
  [domain-prefs]="patch-koha-sysprefs-domain.sh"
  [identity-provider]="patch-koha-identity-provider.sh"
  [oidc-prefs]="patch-koha-sysprefs-oidc.sh"
  [opac-matomo]="patch-koha-sysprefs-opac-matomo.sh"
  [csp-report-only]="patch-koha-apache-csp-report-only.sh"
  [verify]="patch-koha-conf-xml-verify.sh"
)

selected_modules=()

add_module() {
  local name="$1"
  local existing
  [ -n "${MODULE_SCRIPT[$name]:-}" ] || die "Unknown module: ${name}. Use --list-modules"
  for existing in "${selected_modules[@]:-}"; do
    [ "${existing}" = "${name}" ] && return 0
  done
  selected_modules+=("${name}")
}

add_modules_csv() {
  local raw="$1"
  local normalized item
  normalized="$(printf '%s' "${raw}" | tr ',' ' ')"
  for item in ${normalized}; do
    [ -n "${item}" ] || continue
    add_module "${item}"
  done
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
    --no-restart)
      NO_RESTART=true
      ;;
    --all)
      USE_ALL=true
      ;;
    --modules)
      shift
      [ "$#" -gt 0 ] || die "--modules requires value"
      add_modules_csv "$1"
      ;;
    --module)
      shift
      [ "$#" -gt 0 ] || die "--module requires value"
      add_module "$1"
      ;;
    --list-modules)
      LIST_MODULES=true
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
[ -f "${ENV_FILE}" ] || die ".env file not found: ${ENV_FILE}"

if ${LIST_MODULES}; then
  printf 'Available modules:\n'
  for name in "${MODULE_ORDER[@]}"; do
    printf ' - %s (%s)\n' "${name}" "${MODULE_SCRIPT[$name]}"
  done
  exit 0
fi

if ${USE_ALL} || [ "${#selected_modules[@]}" -eq 0 ]; then
  selected_modules=("${MODULE_ORDER[@]}")
fi

log "Selected modules: ${selected_modules[*]}"

index=0
needs_restart=false
has_patch_module=false
for mod in "${selected_modules[@]}"; do
  if [ "${mod}" != "verify" ]; then
    has_patch_module=true
    break
  fi
done

for mod in "${selected_modules[@]}"; do
  if ${DRY_RUN} && ${has_patch_module} && [ "${mod}" = "verify" ]; then
    log "Skipping verify in dry-run because patch modules do not modify files"
    continue
  fi

  script_path="${SCRIPT_DIR}/patch/${MODULE_SCRIPT[$mod]}"
  [ -x "${script_path}" ] || die "Module script is missing or not executable: ${script_path}"

  cmd=("${script_path}" --env-file "${ENV_FILE}" --wait-timeout "${WAIT_TIMEOUT}")
  if ${DRY_RUN}; then
    cmd+=(--dry-run)
  fi
  if [ "${index}" -gt 0 ]; then
    cmd+=(--no-wait)
  fi

  log "Running module: ${mod}"
  "${cmd[@]}"

  if [ "${mod}" != "verify" ]; then
    needs_restart=true
  fi

  index=$((index + 1))
done

if ${DRY_RUN}; then
  log "DRY-RUN: skip koha restart"
  exit 0
fi

if ${NO_RESTART}; then
  log "Skip restart (--no-restart)"
  exit 0
fi

if ${needs_restart}; then
  log "Restarting koha to apply patched live config"
  docker compose -f "${PROJECT_ROOT}/docker-compose.yaml" --env-file "${ENV_FILE}" up -d koha >/dev/null
  log "Restart complete"
else
  log "No patch module requiring restart was run"
fi
