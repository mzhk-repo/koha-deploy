#!/usr/bin/env bash
# Behavior check: indexer process shutdown is bounded and escalates from TERM to KILL.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/container/koha-es-indexer-process.sh"

sleep 60 &
pid="$!"
stop_indexer "${pid}"
! kill -0 "${pid}" 2>/dev/null

bash -c 'trap "" TERM; while :; do read -t 1 _ || :; done' &
pid="$!"
if stop_indexer "${pid}" 2>/dev/null; then
  printf 'ERROR: TERM-ignoring process was not reported as forced down\n' >&2
  exit 1
fi
! kill -0 "${pid}" 2>/dev/null
printf 'PASS: indexer exits on TERM and TERM-ignoring process is killed after the 10s bound\n'
