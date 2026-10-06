#!/usr/bin/env bash
# Regression check: runtime RabbitMQ and indexer configs are created and named in env.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
mkdir -p "${tmp_dir}/bin"
cat > "${tmp_dir}/bin/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  'config inspect') exit 1 ;;
  'config create') exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "${tmp_dir}/bin/docker"
printf 'KOHA_INSTANCE=library\n' > "${tmp_dir}/input.env"
cp "${tmp_dir}/input.env" "${tmp_dir}/write.env"
PATH="${tmp_dir}/bin:${PATH}" "${PROJECT_ROOT}/scripts/render-versioned-worker-configs.sh" \
  --env-file "${tmp_dir}/input.env" --write-env-file "${tmp_dir}/write.env" >/dev/null

grep -Eq '^RABBITMQ_RUNTIME_CONFIG_NAME=rabbitmq_runtime_config_[a-f0-9]{12}$' "${tmp_dir}/write.env"
grep -Eq '^KOHA_ES_INDEXER_PROCESS_CONFIG_NAME=koha_es_indexer_process_[a-f0-9]{12}$' "${tmp_dir}/write.env"
printf 'PASS: RabbitMQ and indexer Docker configs are versioned into runtime env\n'
