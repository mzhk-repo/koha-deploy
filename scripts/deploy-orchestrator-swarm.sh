#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"


# shellcheck source=scripts/lib/orchestrator-env.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/orchestrator-env.sh"
MODE="${ORCHESTRATOR_MODE:-noop}"
STACK_NAME="${STACK_NAME:-koha}"
ENV_FILE="${ORCHESTRATOR_ENV_FILE:-}"
RUNTIME_ENV_FILE=""
RAW_MANIFEST=""
DEPLOY_MANIFEST=""
RECONCILE_CHANGED_SERVICES=()

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

cleanup() {
  rm -f \
    "${RAW_MANIFEST:-}" \
    "${DEPLOY_MANIFEST:-}" \
    "${RUNTIME_ENV_FILE:-}" \
    "${PROJECT_ROOT}/.koha.stack.raw.*.yml" \
    "${PROJECT_ROOT}/.koha.stack.deploy.*.yml"
  orchestrator_env_cleanup
  find "${PROJECT_ROOT}" -maxdepth 1 -type f \
    \( -name ".${STACK_NAME}.env.*" \
      -o -name ".${STACK_NAME}.stack.raw.*.yml" \
      -o -name ".${STACK_NAME}.stack.deploy.*.yml" \) \
    -delete
}

trap cleanup EXIT

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

render_versioned_env_secret() {
  run_script "versioned runtime env secret" "${SCRIPT_DIR}/render-versioned-env-secret.sh" \
    --env-file "${ENV_FILE}" \
    --write-env-file "${ENV_FILE}" >/dev/null
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

validate_db_volume_preflight() {
  local helper_image="${INIT_VOLUMES_HELPER_IMAGE:-alpine:3.20}"

  load_orchestrator_env_file "${ENV_FILE}"
  [[ -n "${VOL_DB_PATH:-}" ]] || { log "ERROR: VOL_DB_PATH is missing in ${ENV_FILE}"; exit 1; }
  [[ "${VOL_DB_PATH}" == /* ]] || { log "ERROR: VOL_DB_PATH must be absolute: ${VOL_DB_PATH}"; exit 1; }
  log "Resolved VOL_DB_PATH=${VOL_DB_PATH} (environment=${ORCHESTRATOR_RESOLVED_ENVIRONMENT})"

  if [[ "${ORCHESTRATOR_RESOLVED_ENVIRONMENT}" != "prod" ]] || is_true "${ORCHESTRATOR_ALLOW_DB_INIT:-false}"; then
    if [[ "${ORCHESTRATOR_RESOLVED_ENVIRONMENT}" == "prod" ]]; then
      log "WARNING: ORCHESTRATOR_ALLOW_DB_INIT=true permits initialization of an empty MariaDB datadir"
    fi
    return 0
  fi

  command -v docker >/dev/null 2>&1 || { log "ERROR: docker is required to validate existing MariaDB datadir"; exit 1; }
  if ! docker run --rm --mount "type=bind,src=${VOL_DB_PATH},dst=/var/lib/mysql,readonly" "${helper_image}" \
    sh -ceu '[ -f /var/lib/mysql/ibdata1 ] && [ -d /var/lib/mysql/mysql ]'; then
    log "ERROR: production VOL_DB_PATH does not contain an initialized MariaDB datadir: ${VOL_DB_PATH}"
    log "HINT: set ORCHESTRATOR_ALLOW_DB_INIT=true only for an intentional first deployment"
    exit 1
  fi
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
  print_swarm_service_diagnostics "${service_name}"
  exit 1
}

print_swarm_service_diagnostics() {
  local service_name="$1"

  if ! docker service inspect "${service_name}" >/dev/null 2>&1; then
    log "Swarm service not found: ${service_name}"
    return 0
  fi

  log "Recent Swarm tasks for ${service_name}:"
  docker service ps "${service_name}" --no-trunc || true
}

build_swarm_local_images() {
  local compose_file="$1"
  local build_services="${ORCHESTRATOR_SWARM_BUILD_SERVICES:-es}"
  local services=()
  local service before_image_id after_image_id

  read -r -a services <<< "${build_services}"
  if [[ "${#services[@]}" -eq 0 ]]; then
    return 0
  fi

  for service in "${services[@]}"; do
    [[ -n "${service}" ]] || continue
    before_image_id="$(docker compose --env-file "${ENV_FILE}" -f "${compose_file}" images -q "${service}" 2>/dev/null | head -n 1 || true)"
    log "Building Swarm-local image for service: ${service}"
    docker compose --env-file "${ENV_FILE}" -f "${compose_file}" build "${service}"
    after_image_id="$(docker compose --env-file "${ENV_FILE}" -f "${compose_file}" images -q "${service}" 2>/dev/null | head -n 1 || true)"

    if [[ -z "${before_image_id}" || "${before_image_id}" != "${after_image_id}" ]]; then
      add_reconcile_changed_service "${service}"
    fi
  done
}

add_reconcile_changed_service() {
  local service="$1"
  local existing

  for existing in "${RECONCILE_CHANGED_SERVICES[@]:-}"; do
    [[ "${existing}" == "${service}" ]] && return 0
  done

  RECONCILE_CHANGED_SERVICES+=("${service}")
}

swarm_service_has_running_container() {
  local service="$1"
  local service_name="${STACK_NAME}_${service}"

  docker ps -q \
    --filter "label=com.docker.swarm.service.name=${service_name}" \
    --filter "status=running" \
    | head -n 1 \
    | grep -q .
}

swarm_service_has_recent_rejected_task() {
  local service="$1"
  local service_name="${STACK_NAME}_${service}"

  docker service ps "${service_name}" --no-trunc --format '{{.CurrentState}} {{.Error}}' 2>/dev/null \
    | head -n 5 \
    | grep -Eq 'Rejected|Failed|No such image|invalid mount config'
}

swarm_service_needs_reconcile() {
  local service="$1"
  local service_name="${STACK_NAME}_${service}"

  docker service inspect "${service_name}" >/dev/null 2>&1 || return 1

  if ! swarm_service_has_running_container "${service}"; then
    return 0
  fi

  if swarm_service_has_recent_rejected_task "${service}"; then
    return 0
  fi

  return 1
}

force_swarm_service_reconcile() {
  local reconcile_candidates="${ORCHESTRATOR_SWARM_RECONCILE_CANDIDATES:-${ORCHESTRATOR_SWARM_BUILD_SERVICES:-es} koha}"
  local service_list=("${RECONCILE_CHANGED_SERVICES[@]:-}")
  local service service_name

  if [[ -n "${ORCHESTRATOR_SWARM_FORCE_UPDATE_SERVICES:-}" ]]; then
    read -r -a service_list <<< "${ORCHESTRATOR_SWARM_FORCE_UPDATE_SERVICES}"
  else
    read -r -a service_list <<< "${reconcile_candidates}"
    service_list+=("${RECONCILE_CHANGED_SERVICES[@]:-}")
  fi

  if [[ "${#service_list[@]}" -eq 0 || "${ORCHESTRATOR_SWARM_RECONCILE:-smart}" == "off" ]]; then
    return 0
  fi

  for service in "${service_list[@]}"; do
    [[ -n "${service}" ]] || continue
    service_name="${STACK_NAME}_${service}"

    if ! docker service inspect "${service_name}" >/dev/null 2>&1; then
      log "Swarm service not found for reconcile, skip: ${service_name}"
      continue
    fi

    if [[ -n "${ORCHESTRATOR_SWARM_FORCE_UPDATE_SERVICES:-}" ]] \
      || [[ "${ORCHESTRATOR_SWARM_RECONCILE:-smart}" == "force" ]] \
      || swarm_service_needs_reconcile "${service}"; then
      log "Forcing Swarm service reconcile: ${service_name}"
      docker service update --force "${service_name}" >/dev/null
    else
      log "Swarm service is already running; skip reconcile: ${service_name}"
    fi
  done
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

  run_script "Elasticsearch index guard" "${SCRIPT_DIR}/koha-elasticsearch-index-guard.sh" --env-file "${ENV_FILE}" --wait-timeout "${wait_timeout}"

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
  local compose_file swarm_file

  compose_file="$(detect_compose_file)"
  swarm_file="docker-compose.swarm.yml"
  RAW_MANIFEST="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.raw.XXXXXX.yml")"
  DEPLOY_MANIFEST="$(mktemp "${PROJECT_ROOT}/.${STACK_NAME}.stack.deploy.XXXXXX.yml")"

  if [[ -z "${compose_file}" ]]; then
    log "ERROR: compose file not found (expected docker-compose.yaml|yml)"
    exit 1
  fi
  if [[ ! -f "${swarm_file}" ]]; then
    log "ERROR: ${swarm_file} not found"
    exit 1
  fi


  run_validation_scripts "${compose_file}"
  resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}" ENV_FILE
  export ORCHESTRATOR_ENV_FILE="${ENV_FILE}"

  prepare_runtime_env_file
  validate_db_volume_preflight
  render_versioned_env_secret
  run_ansible_secrets_if_configured

  run_pre_deploy_adjacent_scripts
  build_swarm_local_images "${compose_file}"

  log "Rendering Swarm manifest (stack=${STACK_NAME}, env_file=${ENV_FILE})"
  docker compose --env-file "${ENV_FILE}" \
    -f "${compose_file}" \
    -f "${swarm_file}" \
    config > "${RAW_MANIFEST}"

  awk 'NR==1 && $1=="name:" {next} {print}' "${RAW_MANIFEST}" \
    | sed -E 's/^([[:space:]]+cpus: )([0-9]+(\.[0-9]+)?)([[:space:]]*)$/\1"\2"\4/' \
    > "${DEPLOY_MANIFEST}"

  log "Deploying stack ${STACK_NAME}"
  docker stack deploy -c "${DEPLOY_MANIFEST}" "${STACK_NAME}"
  force_swarm_service_reconcile

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
