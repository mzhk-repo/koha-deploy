#!/usr/bin/env bash
# Runtime adapter для скриптів, які виконують команди всередині сервісів.
# Підтримує Docker Compose і Docker Swarm; у Swarm mode має fallback на Compose.

docker_runtime_log() {
  printf '[docker-runtime] %s\n' "$*" >&2
}

docker_runtime_die() {
  docker_runtime_log "ERROR: $*"
  exit 1
}

docker_runtime_detect_compose_file() {
  local project_root="$1"

  if [[ -f "${project_root}/docker-compose.yaml" ]]; then
    printf '%s\n' "${project_root}/docker-compose.yaml"
  elif [[ -f "${project_root}/docker-compose.yml" ]]; then
    printf '%s\n' "${project_root}/docker-compose.yml"
  else
    docker_runtime_die "Compose file not found (expected docker-compose.yaml|yml)"
  fi
}

docker_runtime_mode() {
  local mode="${DOCKER_RUNTIME_MODE:-}"

  if [[ -z "${mode}" ]]; then
    case "${ORCHESTRATOR_MODE:-}" in
      swarm) mode="swarm" ;;
      *) mode="compose" ;;
    esac
  fi

  case "${mode}" in
    compose|swarm) printf '%s\n' "${mode}" ;;
    *) docker_runtime_die "unsupported DOCKER_RUNTIME_MODE=${mode} (expected: compose|swarm)" ;;
  esac
}

docker_runtime_swarm_container_id() {
  local service="$1"
  local stack="${STACK_NAME:-koha}"
  local service_name="${stack}_${service}"

  docker ps -q \
    --filter "label=com.docker.swarm.service.name=${service_name}" \
    --filter "status=running" \
    | head -n 1
}

docker_runtime_wait_for_swarm_container() {
  local service="$1"
  local timeout="${2:-300}"
  local elapsed=0

  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if [[ -n "$(docker_runtime_swarm_container_id "${service}")" ]]; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  return 1
}

docker_runtime_compose_exec() {
  local service="$1"
  shift

  local compose_file="${DOCKER_RUNTIME_COMPOSE_FILE:-${KOHA_COMPOSE_FILE:-}}"
  local env_file="${DOCKER_RUNTIME_ENV_FILE:-${ENV_FILE:-}}"

  [[ -n "${compose_file}" ]] || docker_runtime_die "DOCKER_RUNTIME_COMPOSE_FILE/KOHA_COMPOSE_FILE is not set"

  if [[ -n "${env_file}" ]]; then
    docker compose --env-file "${env_file}" -f "${compose_file}" exec -T "${service}" "$@"
  else
    docker compose -f "${compose_file}" exec -T "${service}" "$@"
  fi
}

docker_runtime_compose_restart_service() {
  local service="$1"
  local compose_file="${DOCKER_RUNTIME_COMPOSE_FILE:-${KOHA_COMPOSE_FILE:-}}"
  local env_file="${DOCKER_RUNTIME_ENV_FILE:-${ENV_FILE:-}}"

  [[ -n "${compose_file}" ]] || docker_runtime_die "DOCKER_RUNTIME_COMPOSE_FILE/KOHA_COMPOSE_FILE is not set"

  if [[ -n "${env_file}" ]]; then
    if docker compose --env-file "${env_file}" -f "${compose_file}" restart "${service}"; then
      return 0
    fi
    docker compose --env-file "${env_file}" -f "${compose_file}" up -d "${service}"
  else
    if docker compose -f "${compose_file}" restart "${service}"; then
      return 0
    fi
    docker compose -f "${compose_file}" up -d "${service}"
  fi
}

docker_runtime_swarm_restart_service() {
  local service="$1"
  local stack="${STACK_NAME:-koha}"
  local service_name="${stack}_${service}"

  if docker service inspect "${service_name}" >/dev/null 2>&1; then
    docker service update --force "${service_name}" >/dev/null
    return 0
  fi

  return 1
}

docker_runtime_restart_service() {
  local service="$1"

  case "$(docker_runtime_mode)" in
    compose)
      docker_runtime_compose_restart_service "${service}"
      ;;
    swarm)
      if docker_runtime_swarm_restart_service "${service}"; then
        return 0
      fi

      docker_runtime_log "WARNING: Swarm service '${STACK_NAME:-koha}_${service}' not found. Fallback на docker compose restart."
      docker_runtime_compose_restart_service "${service}"
      ;;
  esac
}

docker_runtime_swarm_exec() {
  local service="$1"
  shift

  local cid
  cid="$(docker_runtime_swarm_container_id "${service}")"

  if [[ -z "${cid}" ]]; then
    return 1
  fi

  docker exec -i "${cid}" "$@"
}

docker_runtime_exec() {
  local service="$1"
  shift

  case "$(docker_runtime_mode)" in
    compose)
      docker_runtime_compose_exec "${service}" "$@"
      ;;
    swarm)
      local cid
      cid="$(docker_runtime_swarm_container_id "${service}")"
      if [[ -n "${cid}" ]]; then
        docker exec -i "${cid}" "$@"
        return $?
      fi

      docker_runtime_log "WARNING: running Swarm container for service '${STACK_NAME:-koha}_${service}' not found. Fallback на docker compose exec."
      docker_runtime_compose_exec "${service}" "$@"
      ;;
  esac
}
