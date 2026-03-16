#!/usr/bin/env bash
# Script Purpose: Generate managed Apache Content-Security-Policy-Report-Only config for Koha.
# Usage: ./scripts/patch/patch-koha-apache-csp-report-only.sh [--env-file FILE] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-apache-csp-report-only.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --dry-run           Print actions only
  --help              Show help
USAGE
}

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

load_env_file

CSP_REPORT_ONLY_ENABLED="${CSP_REPORT_ONLY_ENABLED:-true}"
CSP_REPORT_ONLY_DEFAULT_SRC="${CSP_REPORT_ONLY_DEFAULT_SRC:-'self'}"
CSP_REPORT_ONLY_SCRIPT_SRC="${CSP_REPORT_ONLY_SCRIPT_SRC:-'self' 'unsafe-inline' https://matomo.pinokew.buzz}"
CSP_REPORT_ONLY_CONNECT_SRC="${CSP_REPORT_ONLY_CONNECT_SRC:-'self' https://matomo.pinokew.buzz}"
CSP_REPORT_ONLY_IMG_SRC="${CSP_REPORT_ONLY_IMG_SRC:-'self' data: https://matomo.pinokew.buzz}"
CSP_REPORT_ONLY_STYLE_SRC="${CSP_REPORT_ONLY_STYLE_SRC:-'self' 'unsafe-inline'}"
CSP_REPORT_ONLY_BASE_URI="${CSP_REPORT_ONLY_BASE_URI:-'self'}"
CSP_REPORT_ONLY_FORM_ACTION="${CSP_REPORT_ONLY_FORM_ACTION:-'self'}"
CSP_REPORT_ONLY_FRAME_ANCESTORS="${CSP_REPORT_ONLY_FRAME_ANCESTORS:-'self'}"
CSP_REPORT_ONLY_REPORT_URI="${CSP_REPORT_ONLY_REPORT_URI:-}"

CSP_FILE="${PROJECT_ROOT}/apache/csp-report-only.conf"

case "${CSP_REPORT_ONLY_ENABLED}" in
  true|false) ;;
  *) die "CSP_REPORT_ONLY_ENABLED must be true or false" ;;
esac

if [ "${CSP_REPORT_ONLY_ENABLED}" = "false" ]; then
  log "CSP Report-Only disabled via CSP_REPORT_ONLY_ENABLED=false"
  if ${DRY_RUN}; then
    log "DRY-RUN: would remove ${CSP_FILE}"
    exit 0
  fi
  rm -f "${CSP_FILE}"
  log "Removed ${CSP_FILE}"
  exit 0
fi

policy="default-src ${CSP_REPORT_ONLY_DEFAULT_SRC}; script-src ${CSP_REPORT_ONLY_SCRIPT_SRC}; connect-src ${CSP_REPORT_ONLY_CONNECT_SRC}; img-src ${CSP_REPORT_ONLY_IMG_SRC}; style-src ${CSP_REPORT_ONLY_STYLE_SRC}; base-uri ${CSP_REPORT_ONLY_BASE_URI}; form-action ${CSP_REPORT_ONLY_FORM_ACTION}; frame-ancestors ${CSP_REPORT_ONLY_FRAME_ANCESTORS}"
if [ -n "${CSP_REPORT_ONLY_REPORT_URI}" ]; then
  policy="${policy}; report-uri ${CSP_REPORT_ONLY_REPORT_URI}"
fi

log "Generating managed CSP Report-Only config: ${CSP_FILE}"
if ${DRY_RUN}; then
  log "DRY-RUN: would write Content-Security-Policy-Report-Only header"
  exit 0
fi

cat > "${CSP_FILE}" <<EOF
# Managed by koha-deploy bootstrap module: csp-report-only
# Do not edit manually. Use .env + scripts/bootstrap-live-configs.sh --module csp-report-only

<IfModule mod_headers.c>
    Header always unset Content-Security-Policy
    Header always set Content-Security-Policy-Report-Only "${policy}"
</IfModule>
EOF

log "Done: CSP Report-Only config generated"