#!/usr/bin/env bash

indexer_is_running() {
  local pid="$1" state
  kill -0 "${pid}" 2>/dev/null || return 1
  state="$(awk '{print $3}' "/proc/${pid}/stat" 2>/dev/null || true)"
  [[ "${state}" != "Z" ]]
}

stop_indexer() {
  local pid="$1" deadline
  if indexer_is_running "${pid}"; then
    kill -TERM "${pid}" 2>/dev/null || true
    deadline=$((SECONDS + 10))
    while indexer_is_running "${pid}"; do
      if [[ "${SECONDS}" -ge "${deadline}" ]]; then
        echo "ERROR: es_indexer_daemon.pl ignored TERM for 10 seconds; sending KILL" >&2
        kill -KILL "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
        return 1
      fi
      sleep 1
    done
  fi
  wait "${pid}" 2>/dev/null || true
  return 0
}
