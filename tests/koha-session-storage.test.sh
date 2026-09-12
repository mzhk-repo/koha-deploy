#!/usr/bin/env bash
# Regression test: session storage contract, bootstrap module and fail-closed preflight stay wired.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${PROJECT_ROOT}/docker-compose.yml"
bootstrap="${PROJECT_ROOT}/scripts/bootstrap-live-configs.sh"
module="${PROJECT_ROOT}/scripts/patch/patch-koha-session-storage.sh"
api_prefs="${PROJECT_ROOT}/scripts/patch/patch-koha-sysprefs-api.sh"

grep -Fq 'KOHA_SESSION_STORAGE: ${KOHA_SESSION_STORAGE:-mysql}' "${compose_file}"
grep -Fq 'KOHA_SESSION_STORAGE=mysql' "${PROJECT_ROOT}/.env.example"
grep -Fq 'patch-koha-session-storage.sh' "${bootstrap}"
grep -Fq 'KOHA_SESSION_STORAGE:-mysql' "${compose_file}"
grep -Fq 'Memcached preflight timed out' "${compose_file}"
grep -Fq 'KOHA_SESSION_STORAGE must be mysql or memcached' "${module}"
grep -Fq 'Memcached session probe ok' "${module}"
grep -Fq 'SessionStorage verify failed' "${module}"
grep -Fq 'RESTPublicAPI=1' "${api_prefs}"
grep -Fq 'api/v1/public/libraries?_per_page=1' "${compose_file}"
grep -Fq 'wget -q -O /dev/null' "${compose_file}"
! grep -Fq 'wget -q --spider http://localhost:' "${compose_file}"

preflight_line="$(grep -nF 'Memcached preflight timed out' "${compose_file}" | cut -d: -f1)"
init_line="$(grep -nF 'exec /init' "${compose_file}" | head -n 1 | cut -d: -f1)"
[[ -n "${preflight_line}" && -n "${init_line}" && "${preflight_line}" -lt "${init_line}" ]]

printf 'PASS: Koha session storage bootstrap and preflight are wired\n'
