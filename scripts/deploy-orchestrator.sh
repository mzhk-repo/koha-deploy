#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

cd "${PROJECT_ROOT}"

if [[ -x "./scripts/verify-env.sh" ]]; then
  log "Running verify-env.sh"
  bash ./scripts/verify-env.sh
else
  log "verify-env.sh not found, skipping"
fi

if [[ -x "./scripts/bootstrap-live-configs.sh" ]]; then
  log "bootstrap-live-configs.sh detected; run it separately after deploy if post-deploy patching is required"
fi

log "Orchestration script completed"
