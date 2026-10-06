#!/usr/bin/env bash
# Regression check: RabbitMQ keepalives and 10/30 watchdog values reach Compose and Swarm.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for file in docker-compose.yml docker-compose.swarm.yml; do
  grep -Fq 'net.ipv4.tcp_keepalive_time: "30"' "${PROJECT_ROOT}/${file}"
  grep -Fq 'net.ipv4.tcp_keepalive_intvl: "10"' "${PROJECT_ROOT}/${file}"
  grep -Fq 'net.ipv4.tcp_keepalive_probes: "4"' "${PROJECT_ROOT}/${file}"
done
grep -Fq 'stomp.tcp_listen_options.keepalive = true' "${PROJECT_ROOT}/rabbitmq/rabbitmq.conf"
for key in KOHA_ES_INDEXER KOHA_WORKER; do
  grep -Fq "${key}_MONITOR_INTERVAL=10" "${PROJECT_ROOT}/.env.example"
  grep -Fq "${key}_CONSUMER_GRACE_SECONDS=30" "${PROJECT_ROOT}/.env.example"
done
grep -Fq 'timeout 7 runuser' "${PROJECT_ROOT}/scripts/container/koha-background-worker-supervisor.sh"
grep -Fq 'timeout 7 runuser' "${PROJECT_ROOT}/docker-compose.yml"

printf 'PASS: STOMP keepalive and 10/30 watchdog config are wired\n'
