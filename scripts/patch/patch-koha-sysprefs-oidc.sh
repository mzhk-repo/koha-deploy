#!/usr/bin/env bash
# Script Purpose: Discover and patch Koha OIDC-related system preferences from env (IaC).
# Usage: ./scripts/patch/patch-koha-sysprefs-oidc.sh [--env-file FILE] [--discover] [--apply] [--verify] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

DO_DISCOVER=true
DO_APPLY=true
DO_VERIFY=true
FLAGS_SEEN=false

declare -a OIDC_PREF_KEYS=()
declare -a OIDC_PREF_VALUES=()

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-sysprefs-oidc.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --discover          Print current OIDC-like sysprefs from DB
  --apply             Apply OIDC sysprefs from env keys KOHA_OIDC_PREF__*
  --verify            Verify DB values match env keys KOHA_OIDC_PREF__*
  --dry-run           Print actions only
  --help              Show help

Selection behavior:
  By default script runs discover + apply + verify.
  If at least one of --discover/--apply/--verify is explicitly provided,
  only selected actions are executed.

Env model:
  KOHA_OIDC_PREF__<SystemPreference>=<value>
  Example: KOHA_OIDC_PREF__SomeOIDCPref=1

Notes:
  - Empty values are skipped by default to avoid accidental secret wipe.
  - Set KOHA_OIDC_INCLUDE_EMPTY=true to allow applying empty values.
USAGE
}

parse_args() {
  local rest=()
  # shellcheck disable=SC2034
  local arg

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --discover|--apply|--verify)
        if ! ${FLAGS_SEEN}; then
          DO_DISCOVER=false
          DO_APPLY=false
          DO_VERIFY=false
          FLAGS_SEEN=true
        fi
        case "$1" in
          --discover) DO_DISCOVER=true ;;
          --apply) DO_APPLY=true ;;
          --verify) DO_VERIFY=true ;;
        esac
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        rest+=("$1")
        ;;
    esac
    shift
  done

  if ! parse_common_args "${rest[@]}"; then
    usage
    exit 0
  fi
}

sql_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\'/\'\'}"
  printf '%s' "${v}"
}

collect_pref_mappings() {
  local include_empty="${KOHA_OIDC_INCLUDE_EMPTY:-false}"
  local key value pref_name

  while IFS='=' read -r key value; do
    case "${key}" in
      KOHA_OIDC_PREF__*)
        pref_name="${key#KOHA_OIDC_PREF__}"
        [[ -n "${pref_name}" ]] || continue
        [[ "${pref_name}" =~ ^[A-Za-z0-9_]+$ ]] || die "Invalid syspref key suffix in env var ${key}"

        if [ -z "${value}" ] && [ "${include_empty}" != "true" ]; then
          warn "Skipping ${key}: empty value (set KOHA_OIDC_INCLUDE_EMPTY=true to include)"
          continue
        fi

        OIDC_PREF_KEYS+=("${pref_name}")
        OIDC_PREF_VALUES+=("${value}")
        ;;
    esac
  done < <(env)

  if [ "${#OIDC_PREF_KEYS[@]}" -eq 0 ]; then
    warn "No KOHA_OIDC_PREF__* mappings found in ${ENV_FILE}; apply/verify will be no-op"
  fi
}

discover_oidc_prefs() {
  local sql
  sql="
SELECT variable, value
FROM systempreferences
WHERE LOWER(variable) REGEXP 'oidc|openid|oauth|sso'
ORDER BY variable;
"

  log "Discovering current OIDC-like systempreferences"
  docker compose --env-file "${ENV_FILE}" -f "${PROJECT_ROOT}/docker-compose.yaml" exec -T \
    db mariadb -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" -e "${sql}"
}

apply_oidc_prefs() {
  local i pref_name pref_value pref_name_sql pref_value_sql sql

  [ "${#OIDC_PREF_KEYS[@]}" -gt 0 ] || return 0

  sql=""
  for i in "${!OIDC_PREF_KEYS[@]}"; do
    pref_name="${OIDC_PREF_KEYS[$i]}"
    pref_value="${OIDC_PREF_VALUES[$i]}"
    pref_name_sql="$(sql_escape "${pref_name}")"
    pref_value_sql="$(sql_escape "${pref_value}")"
    sql+="UPDATE systempreferences SET value='${pref_value_sql}' WHERE variable='${pref_name_sql}';"
    sql+=$'\n'
  done

  sql+="SELECT variable, value FROM systempreferences WHERE variable IN ("
  for i in "${!OIDC_PREF_KEYS[@]}"; do
    pref_name_sql="$(sql_escape "${OIDC_PREF_KEYS[$i]}")"
    if [ "${i}" -gt 0 ]; then
      sql+=","
    fi
    sql+="'${pref_name_sql}'"
  done
  sql+=") ORDER BY variable;"

  log "Applying OIDC sysprefs from env mappings (${#OIDC_PREF_KEYS[@]} keys)"

  if ${DRY_RUN}; then
    log "DRY-RUN: skip DB update"
    return 0
  fi

  docker compose --env-file "${ENV_FILE}" -f "${PROJECT_ROOT}/docker-compose.yaml" exec -T \
    db mariadb -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" -e "${sql}"
}

verify_oidc_prefs() {
  local i pref_name pref_value pref_name_sql actual

  [ "${#OIDC_PREF_KEYS[@]}" -gt 0 ] || return 0

  log "Verifying OIDC sysprefs against env mappings"
  for i in "${!OIDC_PREF_KEYS[@]}"; do
    pref_name="${OIDC_PREF_KEYS[$i]}"
    pref_value="${OIDC_PREF_VALUES[$i]}"
    pref_name_sql="$(sql_escape "${pref_name}")"

    actual="$(docker compose --env-file "${ENV_FILE}" -f "${PROJECT_ROOT}/docker-compose.yaml" exec -T \
      db mariadb -N -B -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" \
      -e "SELECT value FROM systempreferences WHERE variable='${pref_name_sql}' LIMIT 1;")"

    if [ "${actual}" != "${pref_value}" ]; then
      die "Mismatch for ${pref_name}: expected env value but got different DB value"
    fi
  done

  log "Verification passed for ${#OIDC_PREF_KEYS[@]} OIDC sysprefs"
}

main() {
  parse_args "$@"
  load_env_file

  [ -n "${DB_ROOT_PASS:-}" ] || die "DB_ROOT_PASS is required in ${ENV_FILE}"
  [ -n "${DB_NAME:-}" ] || die "DB_NAME is required in ${ENV_FILE}"

  collect_pref_mappings

  ${DO_DISCOVER} && discover_oidc_prefs
  ${DO_APPLY} && apply_oidc_prefs
  ${DO_VERIFY} && verify_oidc_prefs

  log "Done: OIDC sysprefs workflow"
}

main "$@"
