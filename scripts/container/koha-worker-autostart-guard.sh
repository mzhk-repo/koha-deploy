#!/usr/bin/env bash
set -euo pipefail

mode="${KOHA_BACKGROUND_WORKERS_AUTOSTART:-true}"

case "${mode}" in
  true|false) ;;
  *)
    printf 'ERROR: KOHA_BACKGROUND_WORKERS_AUTOSTART must be true or false\n' >&2
    exit 64
    ;;
esac

if [[ "${mode}" == "true" ]]; then
  exec /usr/sbin/koha-worker "$@"
fi

for arg in "$@"; do
  case "${arg}" in
    --start)
      printf 'Skipping legacy koha-worker start; workers are managed by dedicated services\n' >&2
      exit 0
      ;;
    --restart)
      printf 'ERROR: legacy koha-worker restart is disabled; restart koha-worker-default or koha-worker-long-tasks\n' >&2
      exit 1
      ;;
  esac
done

exec /usr/sbin/koha-worker "$@"
