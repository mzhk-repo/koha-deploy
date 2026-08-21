#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${KOHA_WORKER_RUNTIME_DIR:-/run/koha-background-workers}"
QUEUE="${KOHA_WORKER_QUEUE:-}"
WAIT_TIMEOUT="${KOHA_WORKER_WAIT_TIMEOUT:-300}"
MONITOR_INTERVAL="${KOHA_WORKER_MONITOR_INTERVAL:-30}"
CONSUMER_GRACE_SECONDS="${KOHA_WORKER_CONSUMER_GRACE_SECONDS:-90}"
DRAIN_TIMEOUT="${KOHA_WORKER_DRAIN_TIMEOUT:-300}"
MAX_PROCESSES="${MAX_PROCESSES:-1}"
WORKER_PID=""
PID_FILE=""
STATUS_FILE=""

log() { printf '[koha-background-worker] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

validate_positive_integer() {
  local name="$1" value="$2"
  [[ "${value}" =~ ^[0-9]+$ && "${value}" -ge 1 ]] || die "${name} must be a positive integer"
}

validate_configuration() {
  case "${QUEUE}" in
    default|long_tasks) ;;
    *) die "KOHA_WORKER_QUEUE must be default or long_tasks" ;;
  esac

  validate_positive_integer KOHA_WORKER_WAIT_TIMEOUT "${WAIT_TIMEOUT}"
  validate_positive_integer KOHA_WORKER_MONITOR_INTERVAL "${MONITOR_INTERVAL}"
  validate_positive_integer KOHA_WORKER_CONSUMER_GRACE_SECONDS "${CONSUMER_GRACE_SECONDS}"
  validate_positive_integer KOHA_WORKER_DRAIN_TIMEOUT "${DRAIN_TIMEOUT}"
  validate_positive_integer MAX_PROCESSES "${MAX_PROCESSES}"
  [[ "${CONSUMER_GRACE_SECONDS}" -ge "${MONITOR_INTERVAL}" ]] || die "KOHA_WORKER_CONSUMER_GRACE_SECONDS must be >= KOHA_WORKER_MONITOR_INTERVAL"
}

prepare_paths() {
  PID_FILE="${RUNTIME_DIR}/${QUEUE}.pid"
  STATUS_FILE="${RUNTIME_DIR}/${QUEUE}.status"
}

jobs_notification_method() {
  runuser --preserve-environment -u "${KOHA_INSTANCE}-koha" -- \
    perl -I/usr/share/koha/lib -MC4::Context -e 'print C4::Context->preference(q(JobsNotificationMethod)) // q(STOMP);'
}

rabbitmq_queue_consumers() {
  runuser --preserve-environment -u "${KOHA_INSTANCE}-koha" -- \
    perl -I/usr/share/koha/lib -MHTTP::Tiny -MXML::LibXML -MMIME::Base64=encode_base64 -MC4::Context -e '
      sub xml_value {
        my ($doc, $name) = @_;
        my ($node) = $doc->findnodes("//message_broker/$name");
        return $node ? $node->textContent : "";
      }
      sub url_escape {
        my ($value) = @_;
        $value =~ s/([^A-Za-z0-9_.~-])/sprintf("%%%02X", ord($1))/eg;
        return $value;
      }
      my $doc = XML::LibXML->load_xml(location => $ENV{KOHA_CONF});
      my $host = xml_value($doc, "hostname") || $ENV{MB_HOST} || "rabbitmq";
      my $user = xml_value($doc, "username") || $ENV{MB_USER} || "";
      my $pass = xml_value($doc, "password") || "";
      my $vhost = xml_value($doc, "vhost") || "/";
      my $namespace = C4::Context->config("memcached_namespace") || "koha_" . ($ENV{KOHA_INSTANCE} || "library");
      my $queue = $namespace . "-" . $ENV{KOHA_WORKER_QUEUE};
      my $auth = encode_base64("$user:$pass", "");
      my $url = "http://$host:15672/api/queues/" . url_escape($vhost) . "/" . url_escape($queue);
      my $response = HTTP::Tiny->new(timeout => 5)->get($url, { headers => { Authorization => "Basic $auth" } });
      exit 2 unless $response->{success};
      my ($consumers) = $response->{content} =~ /"consumers"\s*:\s*(\d+)/;
      print defined($consumers) ? $consumers : 0;
    '
}

tcp_probe() {
  local endpoint="$1" default_port="$2" host port
  endpoint="${endpoint#http://}"
  endpoint="${endpoint#https://}"
  endpoint="${endpoint%%/*}"
  host="${endpoint%%:*}"
  port="${endpoint##*:}"
  [[ "${port}" == "${endpoint}" ]] && port="${default_port}"
  timeout 3 bash -c "</dev/tcp/${host}/${port}"
}

wait_until() {
  local label="$1"
  shift
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  until "$@"; do
    [[ "${SECONDS}" -lt "${deadline}" ]] || die "timeout waiting for ${label}"
    sleep 3
  done
}

worker_has_children() {
  pgrep -P "${WORKER_PID}" >/dev/null 2>&1
}

worker_is_running() {
  local state
  kill -0 "${WORKER_PID}" 2>/dev/null || return 1
  state="$(awk '{print $3}' "/proc/${WORKER_PID}/stat" 2>/dev/null || true)"
  [[ "${state}" != "Z" ]]
}

drain_worker() {
  [[ -n "${WORKER_PID}" ]] || return 0
  kill -0 "${WORKER_PID}" 2>/dev/null || return 0

  log "Draining ${QUEUE} worker (timeout=${DRAIN_TIMEOUT}s)"
  kill -STOP "${WORKER_PID}" 2>/dev/null || true
  local deadline=$((SECONDS + DRAIN_TIMEOUT))
  while worker_has_children && [[ "${SECONDS}" -lt "${deadline}" ]]; do
    sleep 2
  done
  kill -CONT "${WORKER_PID}" 2>/dev/null || true
  kill "${WORKER_PID}" 2>/dev/null || true
  wait "${WORKER_PID}" 2>/dev/null || true
}

abort_worker() {
  [[ -n "${WORKER_PID}" ]] || return 0
  kill -0 "${WORKER_PID}" 2>/dev/null || return 0

  log "Stopping ${QUEUE} worker after failed consumer ownership check"
  kill "${WORKER_PID}" 2>/dev/null || true
  local deadline=$((SECONDS + 10))
  while kill -0 "${WORKER_PID}" 2>/dev/null && [[ "${SECONDS}" -lt "${deadline}" ]]; do
    sleep 1
  done
  kill -KILL "${WORKER_PID}" 2>/dev/null || true
  wait "${WORKER_PID}" 2>/dev/null || true
}

cleanup() {
  if [[ -n "${PID_FILE}" && -f "${PID_FILE}" ]] && [[ "$(cat "${PID_FILE}" 2>/dev/null || true)" == "${WORKER_PID}" ]]; then
    rm -f "${PID_FILE}" "${STATUS_FILE}"
  fi
}

healthcheck() {
  validate_configuration
  prepare_paths
  [[ -s "${PID_FILE}" && -s "${STATUS_FILE}" ]] || exit 1
  [[ "$(cat "${STATUS_FILE}")" == "healthy" ]] || exit 1
  local pid
  pid="$(cat "${PID_FILE}")"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null
}

if [[ "${1:-}" == "--check" ]]; then
  healthcheck
  exit "$?"
fi

validate_configuration
prepare_paths
mkdir -p "${RUNTIME_DIR}"
chmod 0755 "${RUNTIME_DIR}"
trap 'drain_worker; exit 143' TERM INT
trap cleanup EXIT

export KOHA_HOME=/usr/share/koha
export PERL5LIB=/usr/share/koha/lib

if ! getent group "${KOHA_INSTANCE}-koha" >/dev/null; then
  groupadd --gid "${KOHA_INSTANCE_GID}" "${KOHA_INSTANCE}-koha"
fi
if ! getent passwd "${KOHA_INSTANCE}-koha" >/dev/null; then
  useradd --uid "${KOHA_INSTANCE_UID}" --gid "${KOHA_INSTANCE_GID}" \
    --home-dir "/home/${KOHA_INSTANCE}-koha" --create-home --shell /bin/bash \
    "${KOHA_INSTANCE}-koha"
fi

wait_until koha-conf.xml test -r "${KOHA_CONF}"
wait_until 'Koha database' koha-mysql "${KOHA_INSTANCE}" -N -B -e 'SELECT 1'
[[ "$(jobs_notification_method)" == "STOMP" ]] || die 'JobsNotificationMethod must be STOMP for managed workers'
wait_until 'RabbitMQ STOMP TCP' tcp_probe "${MB_HOST}:${MB_PORT:-61613}" 61613
wait_until 'RabbitMQ STOMP Koha connect' runuser --preserve-environment -u "${KOHA_INSTANCE}-koha" -- \
  perl -I/usr/share/koha/lib -MKoha::BackgroundJob -e 'my $conn=Koha::BackgroundJob->connect; exit 1 unless $conn; $conn->disconnect;'

export MAX_PROCESSES
setpriv --reuid "${KOHA_INSTANCE_UID}" --regid "${KOHA_INSTANCE_GID}" --init-groups \
  /usr/bin/perl /usr/share/koha/bin/workers/background_jobs_worker.pl --queue "${QUEUE}" &
WORKER_PID="$!"
printf '%s\n' "${WORKER_PID}" > "${PID_FILE}"
printf '%s\n' starting > "${STATUS_FILE}"

missing_since=""
while worker_is_running; do
  consumers="$(rabbitmq_queue_consumers 2>/dev/null || printf 0)"
  if [[ "${consumers}" =~ ^[0-9]+$ && "${consumers}" -eq 1 ]]; then
    missing_since=""
    printf '%s\n' healthy > "${STATUS_FILE}"
  else
    if [[ -z "${missing_since}" ]]; then
      missing_since="${SECONDS}"
      log "RabbitMQ consumer missing for ${QUEUE} (consumers=${consumers})"
    elif [[ $((SECONDS - missing_since)) -ge "${CONSUMER_GRACE_SECONDS}" ]]; then
      log "ERROR: RabbitMQ consumer missing for ${QUEUE} for >=${CONSUMER_GRACE_SECONDS}s"
      abort_worker
      exit 1
    fi

    # The supervisor, rather than Docker healthcheck, owns consumer recovery.
    # Reporting unhealthy here makes Swarm send TERM before the grace period
    # elapses; TERM then enters the long normal-drain path and leaves a stale
    # consumer alongside the replacement task. Keep the task healthy until
    # the supervisor aborts it after the configured grace period.
    printf '%s\n' healthy > "${STATUS_FILE}"
  fi
  sleep "${MONITOR_INTERVAL}"
done

wait "${WORKER_PID}"
