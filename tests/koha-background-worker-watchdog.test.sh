#!/usr/bin/env bash
# Behavior check: consumer ownership is stable, recoverable, and bounded by grace.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/container/koha-background-worker-supervisor.sh"

CONSUMER_GRACE_SECONDS=30
missing_since=""
consumer_ownership_status 1 0
[[ "${CONSUMER_OWNERSHIP_STATUS}" == healthy && -z "${missing_since}" ]]
consumer_ownership_status 1 10
[[ "${CONSUMER_OWNERSHIP_STATUS}" == healthy && -z "${missing_since}" ]]

consumer_ownership_status 0 20
[[ "${CONSUMER_OWNERSHIP_STATUS}" == missing && "${missing_since}" == 20 ]]
consumer_ownership_status 0 30
[[ "${CONSUMER_OWNERSHIP_STATUS}" == recovering ]]
consumer_ownership_status 1 31
[[ "${CONSUMER_OWNERSHIP_STATUS}" == healthy && -z "${missing_since}" ]]

consumer_ownership_status 0 40
[[ "${CONSUMER_OWNERSHIP_STATUS}" == missing ]]
consumer_ownership_status 0 70
[[ "${CONSUMER_OWNERSHIP_STATUS}" == failed ]]

printf 'PASS: stable consumer stays healthy, brief loss resets, prolonged loss fails at grace\n'
