#!/usr/bin/env bash
# Script Purpose: Validate secret hygiene: .env untracked, no context leaks, required .dockerignore files present.
# Usage: Run on host: ./scripts/check-secrets-hygiene.sh (used in CI pre-checks).
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "[1/3] Checking that .env is not tracked by git..."
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  fail ".env is tracked by git. Remove it from index and keep it local-only."
fi

echo "[2/3] Checking docker build contexts for local .env files..."
for ctx in rabbitmq elasticsearch memcached; do
  if [ -f "${ctx}/.env" ]; then
    fail "Found ${ctx}/.env inside docker build context."
  fi
done

echo "[3/3] Checking .dockerignore in docker build contexts..."
for ctx in rabbitmq elasticsearch memcached; do
  [ -f "${ctx}/.dockerignore" ] || fail "Missing ${ctx}/.dockerignore"
done

echo "OK: secrets hygiene checks passed."
