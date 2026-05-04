#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="${ORCHESTRATOR_MODE:-noop}"
STACK_NAME="${STACK_NAME:-koha}"
ENV_FILE="${ORCHESTRATOR_ENV_FILE:-/tmp/env.decrypted}"
RUNTIME_ENV_FILE=""

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

detect_compose_file() {
  if [[ -f "docker-compose.yaml" ]]; then
    echo "docker-compose.yaml"
  elif [[ -f "docker-compose.yml" ]]; then
    echo "docker-compose.yml"
  else
    echo ""
  fi
}

run_script() {
  local description="$1"
  local script_path="$2"
  shift 2

  if [[ -x "${script_path}" ]]; then
    log "Running ${description}: ${script_path}"
    "${script_path}" "$@"
  elif [[ -f "${script_path}" ]]; then
    log "Running ${description} via bash: ${script_path}"
    bash "${script_path}" "$@"
  else
    log "ERROR: ${description} script not found: ${script_path}"
    exit 1
  fi
}

run_validation_scripts() {
  local compose_file="$1"

  COMPOSE_FILE="${compose_file}" run_script "env template validation" "${SCRIPT_DIR}/verify-env.sh" --example-only
  COMPOSE_FILE="${compose_file}" run_script "ports policy validation" "${SCRIPT_DIR}/check-internal-ports-policy.sh"
}

run_pre_deploy_adjacent_scripts() {
  run_script "volume initialization" "${SCRIPT_DIR}/init-volumes.sh" --env-file "${ENV_FILE}"
}

runtime_env_has_key() {
  local env_file="$1"
  local expected_key="$2"
  local line key

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue

    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]*export[[:space:]]+//')"
    [[ "${line}" == *"="* ]] || continue

    key="${line%%=*}"
    key="$(printf '%s' "${key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ "${key}" == "${expected_key}" ]]; then
      return 0
    fi
  done < "${env_file}"

  return 1
}

validate_runtime_env_file() {
  local required_keys=(
    VOL_DB_PATH
    VOL_ES_PATH
    VOL_KOHA_CONF
    VOL_KOHA_DATA
    VOL_KOHA_LOGS
  )
  local missing=()
  local key

  if [[ ! -s "${ENV_FILE}" ]]; then
    log "ERROR: runtime env file is missing or empty: ${ENV_FILE}"
    exit 1
  fi

  for key in "${required_keys[@]}"; do
    if ! runtime_env_has_key "${ENV_FILE}" "${key}"; then
      missing+=("${key}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    log "ERROR: runtime env file ${ENV_FILE} is missing required deploy key(s): ${missing[*]}"
    log "HINT: check GitHub environment ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-unset}, SOPS decrypt, and DEPLOY_PROJECT_DIR/repo checkout."
    exit 1
  fi
}

prepare_runtime_env_file() {
  validate_runtime_env_file

  RUNTIME_ENV_FILE="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.env.XXXXXX")"
  cp "${ENV_FILE}" "${RUNTIME_ENV_FILE}"
  chmod 600 "${RUNTIME_ENV_FILE}"
  ENV_FILE="${RUNTIME_ENV_FILE}"
  export ORCHESTRATOR_ENV_FILE="${ENV_FILE}"
}

wait_for_swarm_container() {
  local service="$1"
  local timeout="${2:-300}"
  local elapsed=0
  local service_name="${STACK_NAME}_${service}"

  log "Waiting for Swarm container: ${service_name} (timeout=${timeout}s)"
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if docker ps -q \
      --filter "label=com.docker.swarm.service.name=${service_name}" \
      --filter "status=running" \
      | head -n 1 \
      | grep -q .; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  log "ERROR: timeout waiting for Swarm container: ${service_name}"
  exit 1
}

run_post_deploy_scripts() {
  local wait_timeout="${ORCHESTRATOR_POST_DEPLOY_WAIT_TIMEOUT:-300}"

  wait_for_swarm_container db "${wait_timeout}"
  wait_for_swarm_container koha "${wait_timeout}"

  ORCHESTRATOR_MODE=swarm
  DOCKER_RUNTIME_MODE=swarm
  export ORCHESTRATOR_MODE DOCKER_RUNTIME_MODE STACK_NAME

  run_script "live config bootstrap" "${SCRIPT_DIR}/bootstrap-live-configs.sh" --env-file "${ENV_FILE}"

  wait_for_swarm_container koha "${wait_timeout}"

  run_script "password prefs lockdown" "${SCRIPT_DIR}/koha-lockdown-password-prefs.sh" --env-file "${ENV_FILE}"
}

run_ansible_secrets_if_configured() {
  local infra_repo_path environment inventory_env inventory_path playbook_path

  infra_repo_path="${INFRA_REPO_PATH:-}"
  environment="${ENVIRONMENT_NAME:-}"

  if [[ -z "${infra_repo_path}" ]]; then
    log "INFRA_REPO_PATH is not set; skip ansible secrets refresh"
    return 0
  fi

  if [[ ! -d "${infra_repo_path}" ]]; then
    log "ERROR: INFRA_REPO_PATH does not exist: ${infra_repo_path}"
    exit 1
  fi

  if ! command -v ansible-playbook >/dev/null 2>&1; then
    log "ERROR: ansible-playbook not found on host"
    exit 1
  fi

  case "${environment}" in
    development|dev)
      inventory_env="dev"
      ;;
    production|prod)
      inventory_env="prod"
      ;;
    *)
      log "ERROR: unsupported ENVIRONMENT_NAME=${environment} (expected: development|production)"
      exit 1
      ;;
  esac

  inventory_path="${infra_repo_path}/ansible/inventories/${inventory_env}/hosts.yml"
  playbook_path="${infra_repo_path}/ansible/playbooks/swarm.yml"

  if [[ ! -f "${inventory_path}" ]]; then
    log "ERROR: inventory file not found: ${inventory_path}"
    exit 1
  fi
  if [[ ! -f "${playbook_path}" ]]; then
    log "ERROR: playbook file not found: ${playbook_path}"
    exit 1
  fi

  log "Refreshing Swarm secrets via Ansible (inventory=${inventory_env})"
  ANSIBLE_CONFIG="${infra_repo_path}/ansible/ansible.cfg" \
    ansible-playbook \
    -i "${inventory_path}" \
    "${playbook_path}" \
    --tags secrets
}

deploy_swarm() {
  local compose_file swarm_file raw_manifest deploy_manifest

  compose_file="$(detect_compose_file)"
  swarm_file="docker-compose.swarm.yml"
  raw_manifest="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.raw.XXXXXX.yml")"
  deploy_manifest="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.deploy.XXXXXX.yml")"
  trap 'rm -f "${raw_manifest:-}" "${deploy_manifest:-}" "${RUNTIME_ENV_FILE:-}"' EXIT

  if [[ -z "${compose_file}" ]]; then
    log "ERROR: compose file not found (expected docker-compose.yaml|yml)"
    exit 1
  fi
  if [[ ! -f "${swarm_file}" ]]; then
    log "ERROR: ${swarm_file} not found"
    exit 1
  fi

  run_validation_scripts "${compose_file}"

  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f ".env" ]]; then
      ENV_FILE=".env"
      log "WARNING: env.*.enc не знайдено або ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev-середовища."
    else
      log "ERROR: env file not found (${ORCHESTRATOR_ENV_FILE:-/tmp/env.decrypted}) and .env missing"
      exit 1
    fi
  fi

  prepare_runtime_env_file
  run_ansible_secrets_if_configured

  run_pre_deploy_adjacent_scripts

  log "Rendering Swarm manifest (stack=${STACK_NAME}, env_file=${ENV_FILE})"
  docker compose --env-file "${ENV_FILE}" \
    -f "${compose_file}" \
    -f "${swarm_file}" \
    config > "${raw_manifest}"

  awk 'NR==1 && $1=="name:" {next} {print}' "${raw_manifest}" > "${deploy_manifest}"

  log "Deploying stack ${STACK_NAME}"
  docker stack deploy -c "${deploy_manifest}" "${STACK_NAME}"

  run_post_deploy_scripts

  log "Swarm deploy completed"
}

cd "${PROJECT_ROOT}"

case "${MODE}" in
  noop)
    log "No-op mode. Set ORCHESTRATOR_MODE=swarm to enable Phase 8 Swarm deploy path."
    ;;
  swarm)
    deploy_swarm
    ;;
  *)
    log "ERROR: unknown ORCHESTRATOR_MODE=${MODE}. Supported: noop, swarm"
    exit 1
    ;;
esac
