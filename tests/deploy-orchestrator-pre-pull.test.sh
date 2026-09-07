#!/usr/bin/env bash
# Regression test: pre-pull pulls missing Koha image before stack deploy and skips if already present.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/deploy-orchestrator-swarm.sh"
trap - EXIT

test_env="$(mktemp)"
pull_count_file="$(mktemp)"
printf '0\n' > "${pull_count_file}"
trap 'rm -f "${test_env}" "${pull_count_file}"' EXIT

printf 'KOHA_IMAGE=test-registry/koha:target-digest\n' > "${test_env}"
export ENV_FILE="${test_env}"

mock_image_exists=0
docker() {
  case "$1 $2" in
    'image inspect')
      if [[ "${mock_image_exists}" -eq 1 ]]; then
        return 0
      fi
      return 1
      ;;
    pull*)
      local current
      current="$(<"${pull_count_file}")"
      printf '%s\n' "$((current + 1))" > "${pull_count_file}"
      mock_image_exists=1
      return 0
      ;;
    *)
      printf 'unexpected docker command: %s\n' "$*" >&2
      return 1
      ;;
  esac
}

# Test 1: Image is missing locally -> docker pull called
pre_pull_koha_image
[[ "$(<"${pull_count_file}")" -eq 1 ]] || {
  printf 'ERROR: expected 1 pull for missing image, got %s\n' "$(<"${pull_count_file}")" >&2
  exit 1
}

# Test 2: Image is now present locally -> docker pull not called again
pre_pull_koha_image
[[ "$(<"${pull_count_file}")" -eq 1 ]] || {
  printf 'ERROR: expected pull count to stay 1 for cached image, got %s\n' "$(<"${pull_count_file}")" >&2
  exit 1
}

printf 'PASS: pre_pull_koha_image pulls missing image and skips when already cached\n'
