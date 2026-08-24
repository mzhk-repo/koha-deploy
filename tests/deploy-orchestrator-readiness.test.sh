#!/usr/bin/env bash
# Regression test: a healthy current Swarm task must not enter the retry sleep.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/deploy-orchestrator-swarm.sh"
trap - EXIT

docker() {
  case "$1 $2" in
    'service ps')
      printf '%s\n' 'current-task-id'
      ;;
    'ps -q')
      printf '%s\n' 'healthy-container-id'
      ;;
    'inspect -f')
      printf '%s\n' 'healthy'
      ;;
    *)
      printf 'unexpected docker invocation: %s\n' "$*" >&2
      return 1
      ;;
  esac
}

sleep() {
  printf 'readiness attempted to sleep despite an immediately healthy task\n' >&2
  return 1
}

STACK_NAME=koha
started_at="${SECONDS}"
wait_for_swarm_container koha 300
elapsed=$((SECONDS - started_at))

[[ "${elapsed}" -lt 1 ]] || {
  printf 'healthy readiness took %ss; expected immediate completion\n' "${elapsed}" >&2
  exit 1
}

printf 'PASS: healthy current Swarm task completed readiness in %ss without retry sleep\n' "${elapsed}"
