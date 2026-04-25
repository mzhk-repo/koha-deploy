#!/usr/bin/env bash
# Спільний helper для deploy-adjacent скриптів.
# Читає dotenv без source/eval: ORCHESTRATOR_ENV_FILE -> явний --env-file -> dev fallback .env.

orchestrator_env_log() {
  printf '[orchestrator-env] %s\n' "$*" >&2
}

orchestrator_env_die() {
  orchestrator_env_log "ERROR: $*"
  exit 1
}

resolve_orchestrator_env_file() {
  local project_root="$1"
  local explicit_file="${2:-}"
  local env_file=""

  if [[ -n "${explicit_file}" ]]; then
    env_file="${explicit_file}"
  elif [[ -n "${ORCHESTRATOR_ENV_FILE:-}" ]]; then
    env_file="${ORCHESTRATOR_ENV_FILE}"
  elif [[ -f "${project_root}/.env" ]]; then
    env_file="${project_root}/.env"
    orchestrator_env_log "WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev-середовища."
  else
    orchestrator_env_die "env file не знайдено. Передай ORCHESTRATOR_ENV_FILE або --env-file, або поклади .env для локального dev."
  fi

  [[ -f "${env_file}" ]] || orchestrator_env_die "env file не знайдено: ${env_file}"
  printf '%s\n' "${env_file}"
}

load_orchestrator_env_file() {
  local env_file="$1"
  local line key value

  [[ -f "${env_file}" ]] || orchestrator_env_die "env file не знайдено: ${env_file}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue

    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]*export[[:space:]]+//')"
    [[ "${line}" == *"="* ]] || orchestrator_env_die "Invalid dotenv line in ${env_file}: ${line}"

    key="${line%%=*}"
    value="${line#*=}"

    key="$(printf '%s' "${key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || orchestrator_env_die "Invalid dotenv key in ${env_file}: ${key}"

    value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "${key}=${value}"
  done < "${env_file}"
}
