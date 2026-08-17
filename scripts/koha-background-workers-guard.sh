#!/usr/bin/env bash
# Script Purpose: Verify that STOMP workers are isolated from the Koha web task.
# Usage: ./scripts/koha-background-workers-guard.sh [--env-file FILE] [--wait-timeout SEC]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/orchestrator-env.sh"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/docker-runtime.sh"

ENV_FILE=""
WAIT_TIMEOUT="300"

usage() {
  cat <<'USAGE'
Usage: ./scripts/koha-background-workers-guard.sh [options]

Options:
  --env-file FILE       Runtime environment file
  --wait-timeout SEC    Time to wait for worker consumers (default: 300)
  --help                Show this help
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --wait-timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${WAIT_TIMEOUT}" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: --wait-timeout must be a positive integer\n' >&2; exit 2; }

resolve_orchestrator_env_file "${PROJECT_ROOT}" "${ENV_FILE}" ENV_FILE
export ORCHESTRATOR_ENV_FILE="${ENV_FILE}"
DOCKER_RUNTIME_MODE="${DOCKER_RUNTIME_MODE:-swarm}"
STACK_NAME="${STACK_NAME:-koha}"
export DOCKER_RUNTIME_MODE STACK_NAME

worker_process_count() {
  local service="$1"
  docker_runtime_exec "${service}" sh -ec \
    "ps -eo args | awk '/[b]ackground_jobs_worker\\.pl --queue ${2}/ { count++ } END { print count + 0 }'"
}

consumer_count() {
  local service="$1"
  local queue="$2"
  docker_runtime_exec "${service}" sh -ec \
    "runuser --preserve-environment -u \"\$KOHA_INSTANCE-koha\" -- perl -I/usr/share/koha/lib -MHTTP::Tiny -MXML::LibXML -MMIME::Base64=encode_base64 -MC4::Context -e '
      sub xml_value { my (\$doc, \$name) = @_; my (\$node) = \$doc->findnodes(qq{//message_broker/\$name}); return \$node ? \$node->textContent : q{}; }
      sub url_escape { my (\$value) = @_; \$value =~ s/([^A-Za-z0-9_.~-])/sprintf(q{%%%02X}, ord(\$1))/eg; return \$value; }
      my \$doc = XML::LibXML->load_xml(location => \$ENV{KOHA_CONF});
      my \$host = xml_value(\$doc, q{hostname}) || \$ENV{MB_HOST} || q{rabbitmq};
      my \$user = xml_value(\$doc, q{username}) || \$ENV{MB_USER} || q{};
      my \$pass = xml_value(\$doc, q{password}) || q{};
      my \$vhost = xml_value(\$doc, q{vhost}) || q{/};
      my \$namespace = C4::Context->config(q{memcached_namespace}) || q{koha_} . (\$ENV{KOHA_INSTANCE} || q{library});
      my \$auth = encode_base64(qq{\$user:\$pass}, q{});
      my \$url = qq{http://\$host:15672/api/queues/} . url_escape(\$vhost) . q{/} . url_escape(\$namespace . q{-${queue}});
      my \$response = HTTP::Tiny->new(timeout => 5)->get(\$url, { headers => { Authorization => qq{Basic \$auth} } });
      die qq{RabbitMQ Management API request failed\\n} unless \$response->{success};
      my (\$consumers) = \$response->{content} =~ /\"consumers\"\\s*:\\s*(\\d+)/;
      print defined(\$consumers) ? \$consumers : 0;
    '"
}

for pair in 'koha-worker-default default' 'koha-worker-long-tasks long_tasks'; do
  read -r service queue <<<"${pair}"
  elapsed=0
  while :; do
    count="$(worker_process_count "${service}" "${queue}")"
    consumers="$(consumer_count "${service}" "${queue}")"
    if [[ "${count}" == "1" && "${consumers}" == "1" ]]; then
      printf '%s: one worker process and one consumer on %s\n' "${service}" "${queue}"
      break
    fi
    if (( elapsed >= WAIT_TIMEOUT )); then
      printf 'ERROR: %s expected one worker and one consumer on %s; got workers=%s consumers=%s\n' \
        "${service}" "${queue}" "${count}" "${consumers}" >&2
      exit 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
done

web_workers="$(docker_runtime_exec koha sh -ec "ps -eo args | awk '/[b]ackground_jobs_worker\\.pl/ { count++ } END { print count + 0 }'")"
if [[ "${web_workers}" != "0" ]]; then
  printf 'ERROR: koha web task still has %s embedded background worker process(es)\n' "${web_workers}" >&2
  exit 1
fi

printf 'koha: no embedded background worker processes\n'
