#!/usr/bin/env bash
# Regression test: retry only the transient Swarm optimistic update conflict.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/deploy-orchestrator-swarm.sh"
trap - EXIT

state_file="$(mktemp)"
sleep_calls=0
trap 'rm -f "${state_file}"' EXIT

docker() {
  if [[ "$1 $2 $3" != 'stack deploy -c' ]]; then
    printf 'unexpected docker invocation: %s\n' "$*" >&2
    return 1
  fi

  deploy_calls="$(<"${state_file}")"
  deploy_calls=$((deploy_calls + 1))
  printf '%s\n' "${deploy_calls}" > "${state_file}"
  if [[ "${deploy_calls}" -eq 1 ]]; then
    printf '%s\n' 'failed to update service koha_koha-es-indexer: rpc error: code = Unknown desc = update out of sequence' >&2
    return 1
  fi

  printf '%s\n' 'Updating service koha_koha-es-indexer'
}

sleep() {
  [[ "$1" == '0' ]] || {
    printf 'unexpected retry delay: %s\n' "$1" >&2
    return 1
  }
  ((sleep_calls += 1))
}

STACK_NAME=koha
DEPLOY_MANIFEST=/tmp/koha-stack.yml
ORCHESTRATOR_SWARM_DEPLOY_ATTEMPTS=2
ORCHESTRATOR_SWARM_DEPLOY_RETRY_DELAY_SECONDS=0

deploy_swarm_stack_manifest

[[ "${sleep_calls}" -eq 1 ]] || {
  printf 'expected one retry delay, got %s\n' "${sleep_calls}" >&2
  exit 1
}

deploy_calls="$(<"${state_file}")"
[[ "${deploy_calls}" -eq 2 ]] || {
  printf 'expected two deploy attempts, got %s\n' "${deploy_calls}" >&2
  exit 1
}

printf 'PASS: transient Swarm update conflict was retried once\n'
