#!/usr/bin/env bash
# Regression test: destructive image-level DB import stays disabled and DB guard precedes patches.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orchestrator="${PROJECT_ROOT}/scripts/deploy-orchestrator-swarm.sh"

for manifest in compose swarm; do
  compose_args=(-f "${PROJECT_ROOT}/docker-compose.yml")
  [[ "${manifest}" == "compose" ]] || compose_args+=(-f "${PROJECT_ROOT}/docker-compose.swarm.yml")

  rendered="$(
    KOHA_SETUP_SKIP_STEPS=05-custom-step.sh \
    KOHA_APP_ENV_PAYLOAD_SECRET_NAME=test-app-env \
    KOHA_DB_PASSWORD_SECRET_NAME=test-db-password \
    KOHA_DB_ROOT_PASSWORD_SECRET_NAME=test-db-root-password \
    RABBITMQ_PASSWORD_SECRET_NAME=test-rabbitmq-password \
    KOHA_WORKER_AUTOSTART_GUARD_CONFIG_NAME=test-worker-guard \
    KOHA_BACKGROUND_WORKER_SUPERVISOR_CONFIG_NAME=test-worker-supervisor \
      docker compose --env-file "${PROJECT_ROOT}/.env.example" "${compose_args[@]}" config
  )"
  skip_value="$(awk '/^      KOHA_SETUP_SKIP_STEPS:/{print; exit}' <<<"${rendered}")"

  [[ "${skip_value}" == *"05-custom-step.sh"* && "${skip_value}" == *"07-db-import.sh"* ]] || {
    printf 'ERROR: %s manifest does not preserve custom skips and force 07-db-import.sh: %s\n' "${manifest}" "${skip_value}" >&2
    exit 1
  }

  if [[ "${manifest}" == "swarm" ]]; then
    grep -Fq 'export KOHA_SETUP_SKIP_STEPS="$${KOHA_SETUP_SKIP_STEPS:-} 07-db-import.sh"' \
      "${PROJECT_ROOT}/docker-compose.swarm.yml" || {
        printf 'ERROR: Swarm secret payload can override the forced DB import skip\n' >&2
        exit 1
      }
  fi
done

guard_line="$(grep -n 'run_script "Koha DB schema guard"' "${orchestrator}" | cut -d: -f1)"
bootstrap_line="$(grep -n 'run_script "live config bootstrap"' "${orchestrator}" | cut -d: -f1)"

[[ -n "${guard_line}" && -n "${bootstrap_line}" && "${guard_line}" -lt "${bootstrap_line}" ]] || {
  printf 'ERROR: Koha DB schema guard must run before live config bootstrap\n' >&2
  exit 1
}

printf 'PASS: destructive DB import is forced off and schema guard precedes post-deploy patches\n'
