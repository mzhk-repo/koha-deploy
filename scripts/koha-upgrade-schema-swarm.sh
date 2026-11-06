#!/usr/bin/env bash
# Upgrade an existing Koha schema with the configured image on a Swarm manager.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/autonomous-env.sh"
source "${SCRIPT_DIR}/lib/orchestrator-env.sh"

log() { printf '[koha-schema-upgrade] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

if [[ "${1:-}" == "--help" ]]; then
  printf 'Usage: bash scripts/koha-upgrade-schema-swarm.sh --env dev|prod\n'
  exit 0
fi
[[ ( "$#" -eq 2 || "$#" -eq 4 ) && "$1" == "--env" && ( "$2" == dev || "$2" == prod ) ]] || die 'Specify --env dev or --env prod.'
environment="$2"
if [[ "$#" -eq 4 ]]; then
  [[ "$3" == "--env-file" && -r "$4" ]] || die 'Invalid --env-file.'
  load_orchestrator_env_file "$4"
else
  load_autonomous_env "${PROJECT_ROOT}" "${environment}"
fi
lock_name="${STACK_NAME:-koha}-schema-upgrade-lock"
lock_owned=false
migration_started=false
migration_verified=false
cleanup() {
  if [[ "${lock_owned}" == true ]]; then
    if [[ "${migration_started}" == true && "${migration_verified}" == false ]]; then
      log "WARNING: lock ${lock_name} retained; inspect the schema before removing it."
    else
      docker config rm "${lock_name}" >/dev/null 2>&1 || log "WARNING: remove stale lock ${lock_name} manually"
    fi
  fi
  cleanup_autonomous_env
}
trap cleanup EXIT

stack="${STACK_NAME:-koha}"
[[ "${stack}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die 'Invalid STACK_NAME.'
[[ "${KOHA_INSTANCE:-}" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Invalid or missing KOHA_INSTANCE.'
[[ -n "${KOHA_IMAGE:-}" ]] || die 'KOHA_IMAGE is missing.'
for path_var in VOL_DB_PATH VOL_KOHA_CONF VOL_KOHA_DATA VOL_KOHA_LOGS; do
  [[ "${!path_var:-}" == /* ]] || die "${path_var} must be an absolute path."
done
swarm_info="$(docker info --format '{{.Swarm.ControlAvailable}} {{.Swarm.NodeID}}')" || die 'Cannot inspect Swarm state.'
[[ "${swarm_info}" == true\ * ]] || die 'A Swarm manager is required.'
local_node="${swarm_info#true }"
[[ -n "${local_node}" ]] || die 'Cannot identify the local Swarm node.'

services=("${stack}_koha" "${stack}_koha-worker-default" "${stack}_koha-worker-long-tasks" "${stack}_koha-es-indexer")
for service in "${services[@]}" "${stack}_db"; do
  docker service inspect "${service}" >/dev/null || die "Service ${service} not found."
done
check_mount() {
  local service="$1" target="$2" expected="$3" actual
  actual="$(docker service inspect "${service}" --format "{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{if eq .Target \"${target}\"}}{{.Source}}{{end}}{{end}}")" || die "Cannot inspect ${service} mounts."
  [[ "${actual}" == "${expected}" ]] || die "${service} mount ${target} does not match the selected environment."
}
check_mount "${stack}_db" /var/lib/mysql "${VOL_DB_PATH}"
check_mount "${stack}_koha" /etc/koha/sites "${VOL_KOHA_CONF}"
check_mount "${stack}_koha" /var/lib/koha "${VOL_KOHA_DATA}"
check_mount "${stack}_koha" /var/log/koha "${VOL_KOHA_LOGS}"
check_local_tasks() {
  local service="$1" tasks task_id state node
  tasks="$(docker service ps --no-trunc --format '{{.ID}} {{.CurrentState}}' "${service}")" || die "Cannot inspect ${service} tasks."
  while read -r task_id state _; do
    [[ "${state}" =~ ^(New|Pending|Assigned|Accepted|Preparing|Ready|Starting|Running)$ ]] || continue
    node="$(docker inspect --type task "${task_id}" --format '{{.NodeID}}')" || die "Cannot inspect task ${task_id}."
    [[ "${node}" == "${local_node}" ]] || die "An active ${service} task is not on this manager; schema was not upgraded."
  done <<< "${tasks}"
}
for service in "${services[@]}"; do check_local_tasks "${service}"; done
db_ids="$(docker ps -q --filter "label=com.docker.swarm.service.name=${stack}_db")" || die 'Cannot inspect database containers.'
mapfile -t db_containers <<< "${db_ids}"
[[ "${#db_containers[@]}" -eq 1 ]] || die 'Expected exactly one running database container on this node.'
[[ -n "${db_containers[0]}" ]] || die 'Database container is not running.'
rabbit_id="$(docker ps -q --filter "label=com.docker.swarm.service.name=${stack}_rabbitmq")" || die 'Cannot inspect RabbitMQ containers.'
[[ -n "${rabbit_id}" && "${rabbit_id}" != *$'\n'* ]] || die 'Expected exactly one running RabbitMQ container on this node.'
[[ -f "${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml" ]] || die 'Existing koha-conf.xml not found.'

# Config creation is atomic on the Swarm manager and excludes another upgrade invocation.
printf 'Koha schema upgrade lock\n' | docker config create "${lock_name}" - >/dev/null || die "Could not acquire ${lock_name}; check for another upgrade or a stale lock."
lock_owned=true

docker image inspect "${KOHA_IMAGE}" >/dev/null 2>&1 || docker pull "${KOHA_IMAGE}"
run_in_image() {
  docker run --rm --network "container:${db_containers[0]}" \
    --mount "type=bind,src=${VOL_KOHA_CONF},dst=/etc/koha/sites,readonly" \
    --mount "type=bind,src=${VOL_KOHA_DATA},dst=/var/lib/koha" \
    --mount "type=bind,src=${VOL_KOHA_LOGS},dst=/var/log/koha" \
    -e "KOHA_CONF=/etc/koha/sites/${KOHA_INSTANCE}/koha-conf.xml" \
    -e PERL5LIB=/usr/share/koha/lib --entrypoint "$1" "${KOHA_IMAGE}" "${@:2}"
}

# Unlike needs_update.pl, distinguish database errors and reject an image downgrade.
probe_schema() {
  run_in_image perl -MKoha::Installer -MKoha::Database -MKoha -e '
    my ($db) = Koha::Database::dbh()->selectrow_array(q{SELECT value FROM systempreferences WHERE variable = "Version"});
    die "Missing or invalid schema version\n" unless defined($db) && $db =~ /^\d+\.\d+$/;
    my $code = Koha::Installer::TransformToNum(Koha->version);
    print "Database version: $db; image version: ", Koha->version, "\n";
    exit 11 if $db > $code;
    exit(Koha::Installer->needs_update ? 10 : 0);
  '
}

set +e
probe_schema
probe_status=$?
set -e
case "${probe_status}" in
  0) log 'Schema is current; no services were stopped.'; exit 0 ;;
  10) log 'Schema upgrade is required.' ;;
  11) die 'Database version is newer than the configured image; refusing downgrade.' ;;
  *) die "Schema preflight failed (exit ${probe_status})." ;;
esac

wait_stopped() {
  local timeout="$1" service running task_states remaining deadline
  shift
  deadline=$((SECONDS + timeout))
  while :; do
    remaining=false
    for service in "$@"; do
      check_local_tasks "${service}"
      running="$(docker ps -q --filter "label=com.docker.swarm.service.name=${service}")" || die 'Cannot inspect service containers; schema was not upgraded.'
      task_states="$(docker service ps --format '{{.CurrentState}}' "${service}")" || die 'Cannot inspect Swarm tasks; schema was not upgraded.'
      [[ -z "${running}" ]] || remaining=true
      if grep -Eq '^(New|Pending|Assigned|Accepted|Preparing|Ready|Starting|Running)( |$)' <<< "${task_states}"; then remaining=true; fi
    done
    [[ "${remaining}" == false ]] && return 0
    (( SECONDS < deadline )) || die 'Timed out waiting for services to stop; schema was not upgraded. Services remain stopped.'
    sleep 5
  done
}

log 'Stopping web and draining workers; do not start another deploy during this operation.'
docker service scale --detach "${services[0]}=0" >/dev/null
wait_stopped 180 "${services[0]}"

# Wait for in-flight jobs before asking supervisors to drain and stop.
deadline=$((SECONDS + 1800))
while :; do
  queue_status="$(docker exec "${rabbit_id}" rabbitmqctl -q list_queues name messages_unacknowledged)" || die 'Cannot inspect RabbitMQ queues; services remain stopped.'
  set +e
  awk 'NR == 1 { if ($1 != "name" || $2 != "messages_unacknowledged") invalid=1; next }
       NF != 2 || $2 !~ /^[0-9]+$/ { invalid=1; next }
       $2 != 0 { busy=1 }
       END { if (NR == 0 || invalid) exit 2; exit busy ? 1 : 0 }' <<< "${queue_status}"
  queue_result=$?
  set -e
  [[ "${queue_result}" -ne 2 ]] || die 'Unexpected RabbitMQ queue output; services remain stopped.'
  [[ "${queue_result}" -eq 0 ]] && break
  (( SECONDS < deadline )) || die 'Timed out waiting for active jobs; web remains stopped.'
  sleep 5
done
scale_args=()
for service in "${services[@]:1}"; do scale_args+=("${service}=0"); done
docker service scale --detach "${scale_args[@]}" >/dev/null

# The long-tasks supervisor has a 1800-second drain period plus its Swarm stop grace.
wait_stopped 1900 "${services[@]}"

log 'Running Koha schema upgrade. Services will remain stopped if it fails.'
migration_started=true
run_in_image koha-upgrade-schema "${KOHA_INSTANCE}" || die 'Schema upgrade failed; inspect output before any retry or deploy.'
set +e
probe_schema
probe_status=$?
set -e
[[ "${probe_status}" -eq 0 ]] || die "Schema verification failed (exit ${probe_status}); inspect the database before retrying."
migration_verified=true
log 'Schema upgrade verified. Services remain stopped; run the normal deploy to start them with the new image.'
