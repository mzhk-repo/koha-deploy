#!/usr/bin/env bash
# Regression test: docker_runtime_scale_services invokes docker service scale with --detach and all existing services at once.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/lib/docker-runtime.sh"

docker_calls=()

docker() {
  docker_calls+=("$*")
  case "$1 $2" in
    'service inspect')
      return 0
      ;;
    'service scale')
      return 0
      ;;
    'ps -q')
      return 0
      ;;
    *)
      printf 'unexpected docker invocation: %s\n' "$*" >&2
      return 1
      ;;
  esac
}

export DOCKER_RUNTIME_MODE=swarm
export STACK_NAME=koha

docker_runtime_scale_services 0 koha-worker-default koha-worker-long-tasks koha-es-indexer koha es rabbitmq memcached db

# Check that docker service scale was invoked with --detach and all 8 services in a single call
scale_cmd=""
for call in "${docker_calls[@]}"; do
  if [[ "${call}" == "service scale "* ]]; then
    scale_cmd="${call}"
    break
  fi
done

[[ -n "${scale_cmd}" ]] || {
  printf 'ERROR: docker service scale was not called\n' >&2
  exit 1
}

[[ "${scale_cmd}" == *"service scale --detach"* ]] || {
  printf 'ERROR: expected --detach in scale command, got: %s\n' "${scale_cmd}" >&2
  exit 1
}

for svc in koha-worker-default koha-worker-long-tasks koha-es-indexer koha es rabbitmq memcached db; do
  [[ "${scale_cmd}" == *"koha_${svc}=0"* ]] || {
    printf 'ERROR: expected koha_%s=0 in scale command, got: %s\n' "${svc}" "${scale_cmd}" >&2
    exit 1
  }
done

# Check that wait_stack_containers_stopped completes cleanly when ps -q returns empty
docker_runtime_wait_stack_containers_stopped 5

printf 'PASS: docker_runtime_scale_services scales all services in a single detached Swarm call\n'
