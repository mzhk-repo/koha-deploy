#!/usr/bin/env bash
# Script Purpose: Validate compose policy: only allowed services may publish host ports.
# Usage: Run on host: ./scripts/check-internal-ports-policy.sh (fails non-zero on policy violation).
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ -n "${COMPOSE_FILE:-}" ]]; then
  compose_file="${COMPOSE_FILE}"
elif [[ -f "docker-compose.yaml" ]]; then
  compose_file="docker-compose.yaml"
elif [[ -f "docker-compose.yml" ]]; then
  compose_file="docker-compose.yml"
else
  compose_file="docker-compose.yaml"
fi
[ -f "${compose_file}" ] || fail "Compose file not found: ${compose_file}"

# Services that are allowed to publish ports externally.
allowed_raw="${ALLOWED_PUBLISHED_PORT_SERVICES:-koha}"
allowed_normalized="$(echo "${allowed_raw}" | tr ',' ' ' | xargs)"

is_allowed_service() {
  local svc="$1"
  local s
  for s in ${allowed_normalized}; do
    if [ "${svc}" = "${s}" ]; then
      return 0
    fi
  done
  return 1
}

mapfile -t bindings < <(
  awk '
    {
      sub(/\r$/, "", $0)
    }
    /^  [A-Za-z0-9_.-]+:/ {
      svc=$1
      sub(":", "", svc)
      in_ports=0
      next
    }
    /^    ports:/ {
      in_ports=1
      next
    }
    in_ports && /^      - / {
      p=$0
      sub(/^      - /, "", p)
      print svc "|" p
      next
    }
    in_ports && $0 !~ /^      / {
      in_ports=0
    }
  ' "${compose_file}"
)

violations=()
for binding in "${bindings[@]}"; do
  svc="${binding%%|*}"
  port="${binding#*|}"
  if ! is_allowed_service "${svc}"; then
    violations+=("${svc}: ${port}")
  fi
done

if [ "${#violations[@]}" -gt 0 ]; then
  echo "Found disallowed published ports in internal services:" >&2
  printf ' - %s\n' "${violations[@]}" >&2
  fail "Policy violation: only [${allowed_normalized}] may define ports."
fi

echo "OK: internal services do not expose published ports (allowed: ${allowed_normalized})."
