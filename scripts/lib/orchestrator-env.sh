#!/usr/bin/env bash
# Спільний helper для deploy-adjacent скриптів.
# Читає dotenv без source/eval. Production ніколи не використовує неявний .env.

ORCHESTRATOR_RESOLVED_ENVIRONMENT=""
ORCHESTRATOR_AUTO_CLEANUP_ENV_FILE=""

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
  local output_var="${3:-}"
  local env_file=""
  local raw_env target_env enc_file tmp_file

  raw_env="${ENVIRONMENT_NAME:-${SERVER_ENV:-${ENVIRONMENT:-}}}"
  target_env="dev"
  case "${raw_env}" in
    prod|production) target_env="prod" ;;
    dev|development) target_env="dev" ;;
    "")
      if [[ -d "${project_root}/.git" ]] && command -v git >/dev/null 2>&1; then
        local current_branch
        current_branch="$(git -C "${project_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ "${current_branch}" == "main" ]] && target_env="prod"
      fi
      ;;
    *) orchestrator_env_die "unsupported environment: ${raw_env} (expected production|development)" ;;
  esac
  ORCHESTRATOR_RESOLVED_ENVIRONMENT="${target_env}"
  export ORCHESTRATOR_RESOLVED_ENVIRONMENT

  if [[ -n "${explicit_file}" ]]; then
    [[ -f "${explicit_file}" ]] || orchestrator_env_die "explicit env file not found: ${explicit_file}"
    env_file="${explicit_file}"
  elif [[ -n "${ORCHESTRATOR_ENV_FILE:-}" ]]; then
    [[ -f "${ORCHESTRATOR_ENV_FILE}" ]] || orchestrator_env_die "ORCHESTRATOR_ENV_FILE not found: ${ORCHESTRATOR_ENV_FILE}"
    env_file="${ORCHESTRATOR_ENV_FILE}"
  else
    enc_file="${project_root}/env.${target_env}.enc"
    if [[ -f "${enc_file}" ]] && command -v sops >/dev/null 2>&1; then
      orchestrator_env_log "Decrypting ${enc_file} via sops for environment: ${target_env}"
      tmp_file="$(mktemp /dev/shm/env.${target_env}.XXXXXX 2>/dev/null || mktemp /tmp/env.${target_env}.XXXXXX)"
      chmod 600 "${tmp_file}"
      if sops --decrypt --input-type dotenv --output-type dotenv "${enc_file}" > "${tmp_file}"; then
        env_file="${tmp_file}"
        ORCHESTRATOR_AUTO_CLEANUP_ENV_FILE="${tmp_file}"
        export ORCHESTRATOR_AUTO_CLEANUP_ENV_FILE
      else
        rm -f "${tmp_file}"
        orchestrator_env_die "Failed to decrypt ${enc_file} using sops"
      fi
    elif [[ "${target_env}" == "dev" && -f "${project_root}/.env" ]]; then
      env_file="${project_root}/.env"
      orchestrator_env_log "WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev-середовища."
    else
      orchestrator_env_die "env file не знайдено. Передай ORCHESTRATOR_ENV_FILE або налаштуй sops для env.${target_env}.enc"
    fi
  fi

  [[ -f "${env_file}" ]] || orchestrator_env_die "env file не знайдено: ${env_file}"
  if [[ -n "${output_var}" ]]; then
    printf -v "${output_var}" '%s' "${env_file}"
  else
    printf '%s\n' "${env_file}"
  fi
}

orchestrator_env_cleanup() {
  local env_file="${ORCHESTRATOR_AUTO_CLEANUP_ENV_FILE:-}"

  [[ -n "${env_file}" && -f "${env_file}" ]] || return 0
  if command -v shred >/dev/null 2>&1; then
    shred -u "${env_file}" 2>/dev/null || rm -f "${env_file}"
  else
    rm -f "${env_file}"
  fi
  ORCHESTRATOR_AUTO_CLEANUP_ENV_FILE=""
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
