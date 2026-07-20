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

  if [[ -n "${explicit_file}" && -f "${explicit_file}" ]]; then
    env_file="${explicit_file}"
  elif [[ -n "${ORCHESTRATOR_ENV_FILE:-}" && -f "${ORCHESTRATOR_ENV_FILE}" ]]; then
    env_file="${ORCHESTRATOR_ENV_FILE}"
  elif [[ -f "/tmp/env.decrypted" ]]; then
    env_file="/tmp/env.decrypted"
  else
    local raw_env="${ENVIRONMENT_NAME:-${SERVER_ENV:-${ENVIRONMENT:-}}}"
    local target_env="dev"
    case "${raw_env}" in
      prod|production) target_env="prod" ;;
      dev|development) target_env="dev" ;;
      "")
        if [[ -d "${project_root}/.git" ]] && command -v git >/dev/null 2>&1; then
          local current_branch
          current_branch="$(git -C "${project_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
          if [[ "${current_branch}" == "main" ]]; then
            target_env="prod"
          fi
        fi
        ;;
    esac

    local enc_file="${project_root}/env.${target_env}.enc"
    if [[ -f "${enc_file}" ]] && command -v sops >/dev/null 2>&1; then
      orchestrator_env_log "Decrypting ${enc_file} via sops for environment: ${target_env}"
      local tmp_file
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
    elif [[ -f "${project_root}/.env" ]]; then
      env_file="${project_root}/.env"
      orchestrator_env_log "WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev-середовища."
    else
      orchestrator_env_die "env file не знайдено. Передай ORCHESTRATOR_ENV_FILE або --env-file, або мається sops ключ для env.${target_env}.enc"
    fi
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
