#!/usr/bin/env bash
# Regression test: unchanged live config must not force-restart Swarm services.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/conf/library"
printf '%s\n' '<config><timezone>Europe/Kyiv</timezone></config>' > "${TEST_DIR}/conf/library/koha-conf.xml"
printf '%s\n' \
  'KOHA_INSTANCE=library' \
  "VOL_KOHA_CONF=${TEST_DIR}/conf" \
  'KOHA_TIMEZONE=Europe/Kyiv' > "${TEST_DIR}/runtime.env"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''unexpected Docker invocation during no-op bootstrap: %s\n'\'' "$*" >&2' \
  'exit 1' > "${TEST_DIR}/bin/docker"
chmod 0755 "${TEST_DIR}/bin/docker"

output="$(PATH="${TEST_DIR}/bin:${PATH}" bash "${PROJECT_ROOT}/scripts/bootstrap-live-configs.sh" \
  --env-file "${TEST_DIR}/runtime.env" --module timezone)"

grep -Fq 'Live configuration unchanged; skip Swarm service restart' <<<"${output}"
printf 'PASS: unchanged live config completed bootstrap without Docker restart\n'
