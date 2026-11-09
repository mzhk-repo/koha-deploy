#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" "${tmp}/conf/library"
touch "${tmp}/conf/library/koha-conf.xml"
export TEST_TMP="${tmp}" PATH="${tmp}/bin:${PATH}"
cat > "${tmp}/bin/sops" <<'MOCK'
#!/usr/bin/env bash
printf 'KOHA_INSTANCE=library\nKOHA_IMAGE=example/koha:new\nVOL_DB_PATH=%s/db\nVOL_KOHA_CONF=%s/conf\nVOL_KOHA_DATA=%s/data\nVOL_KOHA_LOGS=%s/logs\n' "$TEST_TMP" "$TEST_TMP" "$TEST_TMP" "$TEST_TMP"
MOCK
cat > "${tmp}/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TMP/calls"
case "$1 $2" in
  'info --format') echo 'true local-node' ;;
  'service inspect')
    case "$*" in
      *'--format'*'/var/lib/mysql'*) echo "$TEST_TMP/db" ;;
      *'--format'*'/etc/koha/sites'*) echo "$TEST_TMP/conf" ;;
      *'--format'*'/var/lib/koha'*) echo "$TEST_TMP/data" ;;
      *'--format'*'/var/log/koha'*) echo "$TEST_TMP/logs" ;;
    esac ;;
  'service ps') [[ "${REMOTE_TASK:-0}" != 1 ]] || echo 'task123 Running 1 minute ago' ;;
  'inspect --type') echo remote-node ;;
  'image inspect'|'service scale'|'config rm') : ;;
  'config create') cat >/dev/null; echo lock ;;
  'ps -q')
    case "$*" in
      *koha_db*) echo db-container ;;
      *koha_rabbitmq*) echo rabbit-container ;;
    esac ;;
  'exec rabbit-container') printf 'name\tmessages_unacknowledged\nkoha_library-default\t0\n' ;;
  'run --rm')
    case "$*" in
      *'--entrypoint perl'*)
        count=0
        [[ ! -f "$TEST_TMP/probes" ]] || count=$(cat "$TEST_TMP/probes")
        echo "$((count + 1))" > "$TEST_TMP/probes"
        if [[ "$count" -eq 0 ]]; then exit "${PROBE_FIRST:-10}"; fi
        exit "${PROBE_AFTER:-0}" ;;
      *'--entrypoint koha-upgrade-schema'*) exit "${UPGRADE_EXIT:-0}" ;;
      *) exit 99 ;;
    esac ;;
  *) echo "Unexpected docker command: $*" >&2; exit 99 ;;
esac
MOCK
chmod +x "${tmp}/bin/sops" "${tmp}/bin/docker"
script="${root}/scripts/koha-upgrade-schema-swarm.sh"

PROBE_FIRST=0 bash "${script}" --env dev > "${tmp}/output"
! grep -q 'service scale\|entrypoint koha-upgrade-schema' "${tmp}/calls"
rm -f "${tmp}/calls" "${tmp}/probes"

PROBE_FIRST=10 bash "${script}" --env dev > "${tmp}/output"
grep -q 'service scale --detach koha_koha=0' "${tmp}/calls"
grep -q 'entrypoint koha-upgrade-schema' "${tmp}/calls"
grep -q 'Schema upgrade verified' "${tmp}/output"
rm -f "${tmp}/calls" "${tmp}/probes"

if PROBE_FIRST=11 bash "${script}" --env dev > "${tmp}/output" 2>&1; then exit 1; fi
! grep -q 'service scale\|entrypoint koha-upgrade-schema' "${tmp}/calls"
rm -f "${tmp}/calls" "${tmp}/probes"

if UPGRADE_EXIT=1 bash "${script}" --env dev > "${tmp}/output" 2>&1; then exit 1; fi
grep -q 'Schema upgrade failed' "${tmp}/output"
! grep -q 'Schema upgrade verified' "${tmp}/output"
! grep -q 'config rm koha-schema-upgrade-lock' "${tmp}/calls"
grep -q 'lock koha-schema-upgrade-lock retained' "${tmp}/output"
rm -f "${tmp}/calls" "${tmp}/probes"

if REMOTE_TASK=1 bash "${script}" --env dev > "${tmp}/output" 2>&1; then exit 1; fi
grep -q 'task is not on this manager' "${tmp}/output"
! grep -q 'service scale\|entrypoint koha-upgrade-schema' "${tmp}/calls"
printf 'PASS: schema upgrade preflight, success, downgrade and failure\n'
