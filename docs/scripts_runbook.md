# Runbook: scripts (Koha deploy)

## Env-контракти

- CI/CD decrypt flow: shared workflow розшифровує `env.dev.enc` або `env.prod.enc` у тимчасовий файл і передає шлях через `ORCHESTRATOR_ENV_FILE`.
- Autonomous flow: cron/manual скрипти читають `SERVER_ENV` (`dev|prod`) або аргумент `--env dev|prod`, розшифровують `env.<env>.enc` у `/dev/shm` і очищають tmp-файл після завершення.
- Локальний dev fallback на `.env` дозволений тільки для deploy-adjacent скриптів, коли `ORCHESTRATOR_ENV_FILE` не передано.

## Категорія 1а: validation

### `scripts/check-ports-policy.sh`

#### Бізнес-логіка
- Wrapper для preflight-перевірок портів і env-шаблону.
- Автоматично визначає `docker-compose.yaml` або `docker-compose.yml`.
- Запускає `verify-env.sh --example-only` і `check-internal-ports-policy.sh`.
- Не читає секрети.

#### Manual execution
```bash
bash scripts/check-ports-policy.sh
bash scripts/check-ports-policy.sh docker-compose.yml
```

### `scripts/check-internal-ports-policy.sh`

#### Бізнес-логіка
- Перевіряє compose policy: internal services не повинні публікувати host ports.
- За замовчуванням дозволений published port тільки для `koha`.
- Список дозволених сервісів можна перевизначити через `ALLOWED_PUBLISHED_PORT_SERVICES`.

#### Manual execution
```bash
bash scripts/check-internal-ports-policy.sh
COMPOSE_FILE=docker-compose.yml bash scripts/check-internal-ports-policy.sh
```

### `scripts/verify-env.sh`

#### Бізнес-логіка
- Перевіряє dotenv-синтаксис `.env.example`.
- Звіряє ключі, які використовує compose, з `.env.example`.
- У локальному режимі також звіряє `.env` з `.env.example`.
- `source` у цьому legacy validation-скрипті дозволений правилами refactoring scope.

#### Manual execution
```bash
bash scripts/verify-env.sh --example-only
bash scripts/verify-env.sh --env-file .env --example-file .env.example
```

## Категорія 1б: deploy-adjacent

### RabbitMQ 4.4.0: STOMP connection close compatibility

The official 4.4.0 Management API can return HTTP 204 without closing a native
STOMP connection because it expects `pid` while the connection record exposes
`connection`. The patched module handles this case only for STOMP; the existing
authorization and other connection handling remain in place. The vendored
module is based on RabbitMQ `v4.4.0`'s `rabbit_mgmt_wm_connection.erl`
(unmodified source SHA-256:
`6747f52e77d0caf155b90233b4a48daac847ebec93ffd65b04c3e35d0d32f57d`).
The image is pinned to the tested 4.4.0 base digest; review the patch against
upstream before upgrading either version.

Build the derived image on the manager and run the isolated compatibility test:

```bash
docker build -f rabbitmq/Dockerfile.4.4-stomp-fix -t koha-rabbitmq-stomp-fix:4.4.0 rabbitmq
KOHA_TEST_IMAGE='<your Koha image reference>' bash tests/rabbitmq-44-stomp-close.integration.sh
```

The test starts a disposable broker with no external network and synthetic
credentials. It uses the supplied Koha image as a STOMP client, checks all three
queue names, closes their consumers through the Management API, and checks a
replacement consumer can process a message. It does not run a full Koha job.

Set `RABBITMQ_IMAGE=koha-rabbitmq-stomp-fix:4.4.0` in the target runtime env.
Compose and Swarm use this same image reference. The deploy orchestrator
builds it locally by default; if `ORCHESTRATOR_SWARM_BUILD_SERVICES` is overridden,
include `rabbitmq` or ensure the exact image is available on the RabbitMQ node.
Before changing a live broker, stop job
producers, drain actual running jobs, and verify that its queues are empty. Koha
acknowledges a job before the child process finishes, so zero unacknowledged
messages alone does not establish that all jobs have finished.

### `scripts/koha-upgrade-schema-swarm.sh`

Use this procedure when deploying a newer Koha image to an **existing** database.
It must run on a Swarm manager with Docker and SOPS access. The database and all
active Koha service tasks must be on that manager; the script stops if a Koha
task is active on another node. An empty database must be initialized with the
Koha installer or restored.

1. Make sure `env.dev.enc` contains the intended new `KOHA_IMAGE`, and that the
   image is available to Docker. Stop external systems from submitting Koha jobs
   and ensure no other deploy or schema upgrade runs at the same time.
2. From the repository directory, run:

   ```bash
   cd /opt/Koha/koha-deploy
   bash scripts/koha-upgrade-schema-swarm.sh --env dev
   ```

3. If the script reports `Schema upgrade verified`, run the normal dev deploy.
   The web service, workers and indexer stay stopped until that deploy starts them.
   If it reports `Schema is current`, nothing was stopped and the normal deploy
   can proceed. The script checks all RabbitMQ queues for unacknowledged jobs;
   it waits up to 30 minutes for active jobs and up to another 1,900 seconds for
   workers to stop. Stop external job producers for the whole operation.
4. If the script fails, read the error before taking further action. Services
   already stopped are not restarted automatically. If the upgrade started but
   failed or verification failed, the Swarm config `koha-schema-upgrade-lock`
   remains as a guard. Investigate the database and migration output before
   removing that lock or retrying; the schema could be partially upgraded.

The script uses the image and instance from the selected encrypted environment,
checks the existing schema, refuses a downgrade, and uses Koha's own
`koha-upgrade-schema`. It does not create or require a backup. A backup is
recommended: restoring an older image does not reverse a schema migration, and
without a backup lost data may be unrecoverable. Production execution requires
explicit approval; use `--env prod` only after that approval.

For an explicitly authorized deploy, the upgrade can also run immediately before
the stack update by adding `ORCHESTRATOR_SCHEMA_UPGRADE=true` to the existing
Swarm orchestrator command below. It is disabled by default. Do not run the
standalone script concurrently with deploy: its lock only excludes another
invocation of the schema upgrade script.

### `scripts/deploy-orchestrator-swarm.sh`

#### Бізнес-логіка
- Основний Swarm orchestrator для CI/CD.
- Порядок фаз: validation -> env resolution -> versioned runtime secret/configs -> optional Ansible secrets refresh -> `init-volumes.sh` -> render stack manifest -> `docker stack deploy` -> post-deploy bootstrap/worker guard/index guard/lockdown.
- Перед render stack manifest створює Docker secrets і immutable Docker configs з hash-based назвами. Зміна worker guard/supervisor змінює service spec і запускає контрольований update.
- Якщо існуючий web task має embedded `background_jobs_worker.pl`, спершу deploy-иться `docker-compose.workers-transition.yml` з worker replicas `0`; після підтвердження web без embedded workers deploy-иться фінальний manifest з двома singleton workers.
- Тимчасовий optimistic conflict Swarm `update out of sequence` під час `docker stack deploy` повторюється до 3 разів з паузою 5 секунд (`ORCHESTRATOR_SWARM_DEPLOY_ATTEMPTS`, `ORCHESTRATOR_SWARM_DEPLOY_RETRY_DELAY_SECONDS`); інші помилки deploy одразу повертаються як failure.
- Post-deploy чекає `${STACK_NAME}_db`, `${STACK_NAME}_koha` і обидва worker containers.
- `bootstrap-live-configs.sh`, `koha-background-workers-guard.sh`, `koha-elasticsearch-index-guard.sh` і `koha-lockdown-password-prefs.sh` запускаються після `docker stack deploy` у `DOCKER_RUNTIME_MODE=swarm`.

#### Manual execution
```bash
ENV_TMP="$(mktemp /dev/shm/env-XXXXXX)"
chmod 600 "${ENV_TMP}"
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > "${ENV_TMP}"

ORCHESTRATOR_MODE=swarm \
ORCHESTRATOR_ALLOW_DB_INIT=false \
ENVIRONMENT_NAME=development \
STACK_NAME=koha \
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" \
bash scripts/deploy-orchestrator-swarm.sh
```

#### Cleanup
```bash
shred -u "${ENV_TMP}" 2>/dev/null || rm -f "${ENV_TMP}"
```

#### No-op smoke
```bash
ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh
```

### `scripts/render-versioned-env-secret.sh`

#### Бізнес-логіка
- Створює immutable Docker secrets для runtime env payload і окремих Swarm secrets (`DB_PASS`, `DB_ROOT_PASS`, `RABBITMQ_PASS`).
- Назва кожного secret включає hash payload/значення, тому зміна значень у розшифрованому `env.<env>.enc` створює нову назву secret.
- Generated `*_SECRET_NAME` не входять у env payload hash, щоб уникнути нескінченної зміни hash між деплоями.
- У Swarm orchestrator generated secret names дописуються тільки в тимчасовий env-файл перед `docker compose config`.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" \
  bash scripts/render-versioned-env-secret.sh --write-env-file "${ENV_TMP}"
```

### `scripts/init-volumes.sh`

#### Бізнес-логіка
- Створює bind-mount директорії для MariaDB, Elasticsearch, Koha config/data/logs.
- Нормалізує ownership/permissions.
- Привілейовані дії виконує через root, passwordless sudo або ephemeral Docker helper.
- Env читається через `--env-file` / `ORCHESTRATOR_ENV_FILE` без `source`.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/init-volumes.sh
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/init-volumes.sh --fix-existing
```

### `scripts/bootstrap-live-configs.sh`

#### Бізнес-логіка
- Orchestrator для live Koha patch modules.
- Підтримує `--all`, `--modules`, `--module`, `--list-modules`, `--dry-run`, `--no-restart`.
- Передає `--env-file` кожному patch-модулю.
- Після patch-модулів рестартить `koha` через `docker_runtime_restart_service`.

#### Manual execution
```bash
bash scripts/bootstrap-live-configs.sh --list-modules
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module csp-report-only --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --all
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --modules smtp,verify --no-restart
```

### `scripts/koha-elasticsearch-index-guard.sh`

#### Бізнес-логіка
- Перевіряє, що Koha працює з `SearchEngine=Elasticsearch`.
- Автоматично створює відсутні індекси `koha_${KOHA_INSTANCE}_biblios` і `koha_${KOHA_INSTANCE}_authorities` через `koha-elasticsearch --rebuild --reset`.
- Якщо індекси існують, порівнює count у DB (`biblio`, `auth_header`) з Elasticsearch `_count`.
- За замовчуванням `ORCHESTRATOR_ES_REINDEX_ON_MISMATCH=auto`: reindex запускається тільки коли ES суттєво відстає від DB за `ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT`.
- Після перевірок перезапускає керований сервіс `koha-es-indexer`, щоб daemon перечитав актуальний `SearchEngine` і не залишався у stale Zebra context після bootstrap.
- `koha-es-indexer` винесений в окремий довгоживучий crash-only сервіс: перед стартом чекає `koha-conf.xml`, DB, Elasticsearch TCP і RabbitMQ STOMP, після чого supervisor запускає `es_indexer_daemon.pl` через `setpriv` і перевіряє consumer на RabbitMQ `elastic_index` queue. Watchdog defaults: `KOHA_ES_INDEXER_MONITOR_INTERVAL=10`, `KOHA_ES_INDEXER_CONSUMER_GRACE_SECONDS=30`; Management API запит обмежений зовнішнім timeout 7s. При зупинці daemon отримує TERM, після 10s — KILL і помилковий exit.
- Runtime exec іде через `docker_runtime_exec`, тому підтримує Swarm і Compose fallback.

#### Manual execution
```bash
ORCHESTRATOR_MODE=swarm DOCKER_RUNTIME_MODE=swarm STACK_NAME=koha \
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" \
bash scripts/koha-elasticsearch-index-guard.sh --dry-run
```

#### Runtime checks
```bash
docker service ps koha_koha-es-indexer --no-trunc
docker exec -i "$(docker ps -q --filter label=com.docker.swarm.service.name=koha_rabbitmq)" \
  rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
```

### `scripts/koha-lockdown-password-prefs.sh`

#### Бізнес-логіка
- Вимикає локальне OPAC password reset/change для OIDC-first моделі.
- Патчить `OpacResetPassword=0` і `OpacPasswordChange=0`.
- Виконує apply + verify за замовчуванням.
- Runtime exec іде через `docker_runtime_exec`, тому підтримує Swarm і Compose fallback.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/koha-lockdown-password-prefs.sh --verify
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/koha-lockdown-password-prefs.sh --apply --verify
```

## Patch modules

Усі patch-модулі використовують `scripts/patch/_patch_common.sh`, який парсить common args, читає env через `orchestrator-env.sh`, визначає compose-файл і надає `docker_runtime_exec`.

### XML modules

Файли:
- `scripts/patch/patch-koha-conf-xml-timezone.sh`
- `scripts/patch/patch-koha-conf-xml-trusted-proxies.sh`
- `scripts/patch/patch-koha-conf-xml-memcached.sh`
- `scripts/patch/patch-koha-conf-xml-message-broker.sh`
- `scripts/patch/patch-koha-conf-xml-smtp.sh`
- `scripts/patch/patch-koha-conf-xml-verify.sh`

#### Бізнес-логіка
- Патчать або перевіряють live `${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml`.
- Мають wait-for-file механіку для першого bootstrap.
- `verify` не змінює файл.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module smtp --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module verify --no-restart
```

### DB/systempreferences modules

Файли:
- `scripts/patch/patch-koha-sysprefs-search.sh`
- `scripts/patch/patch-koha-sysprefs-api.sh`
- `scripts/patch/patch-koha-sysprefs-domain.sh`
- `scripts/patch/patch-koha-sysprefs-oidc.sh`
- `scripts/patch/patch-koha-sysprefs-opac-matomo.sh`
- `scripts/patch/patch-koha-identity-provider.sh`

#### Бізнес-логіка
- Оновлюють Koha DB state з env як IaC.
- `search-prefs` керує `systempreferences.SearchEngine` через `KOHA_SEARCH_ENGINE` або `USE_ELASTICSEARCH` і після direct SQL update чистить Koha cache.
- `api-prefs` керує `systempreferences.RESTBasicAuth` через `KOHA_REST_BASIC_AUTH` і після direct SQL update чистить Koha cache.
- DB exec іде через `docker_runtime_exec db ...` або штатний `koha-mysql` через `docker_runtime_exec koha ...`.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module search-prefs --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module api-prefs --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module domain-prefs --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/patch/patch-koha-sysprefs-oidc.sh --discover
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/patch/patch-koha-identity-provider.sh --verify
```

### File/config modules and wrappers

Файли:
- `scripts/patch/patch-koha-apache-csp-report-only.sh`
- `scripts/patch/patch-koha-conf-xml.sh`
- `scripts/patch/patch-koha-templates.sh`

#### Бізнес-логіка
- `csp-report-only` генерує `apache/csp-report-only.conf`.
- `patch-koha-conf-xml.sh` і `patch-koha-templates.sh` є compatibility wrappers для `bootstrap-live-configs.sh`.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module csp-report-only --dry-run
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/patch/patch-koha-conf-xml.sh --dry-run
```

## Категорія 2: autonomous

### `scripts/lib/autonomous-env.sh`

#### Бізнес-логіка
- Спільний helper для cron/manual скриптів.
- Визначає env через `SERVER_ENV` або `--env dev|prod`.
- Розшифровує `env.<env>.enc` у `/dev/shm/env-XXXXXX`, завантажує dotenv без shell-виконання значень і очищає tmp-файл.
- Використовує стандартний SOPS dotenv decrypt: `sops --decrypt --input-type dotenv --output-type dotenv`.

#### Manual execution
```bash
bash -lc 'source scripts/lib/autonomous-env.sh; load_autonomous_env "$PWD" dev; echo "$KOHA_INSTANCE"'
```

### `scripts/backup.sh`

#### Бізнес-логіка
- Створює повний Koha backup set: MariaDB dump, bind-volume архіви, checksums і manifest.
- Основні артефакти: `${DB_NAME}.sql.gz`, `koha_config.tar.gz`, `koha_data.tar.gz`, `SHA256SUMS`, `backup_metadata.env`, `backup_manifest.tsv`.
- Logs і Elasticsearch data архівуються опційно через `BACKUP_INCLUDE_LOGS` / `BACKUP_INCLUDE_ES_DATA`.
- Підтримує lightweight offsite copy через `BACKUP_RCLONE_REMOTE` / `BACKUP_RCLONE_FOLDER`.
- Локальний retention керується `BACKUP_RETENTION_DAYS`, Google Drive/rclone retention — окремо через `BACKUP_RCLONE_RETENTION_DAYS`.
- Пише textfile collector метрики у `${NODE_EXPORTER_TEXTFILE_DIR}/${BACKUP_METRICS_FILE}`:
  - `koha_backup_last_run_timestamp_seconds`
  - `koha_backup_last_success_timestamp_seconds`
  - `koha_backup_last_status`
- `--dry-run` не оновлює freshness metrics.

#### Manual execution
```bash
SERVER_ENV=dev bash scripts/backup.sh
bash scripts/backup.sh --env prod
```

### `scripts/test-restore.sh`

#### Бізнес-логіка
- Restore smoke test для backup set Koha без змін production DB.
- Імпортує SQL dump із backup-директорії у тимчасовий MariaDB container, перевіряє кількість таблиць і прибирає контейнер/тимчасові дані після завершення.
- Якщо `--source` не заданий, бере найсвіжішу директорію з `BACKUP_PATH`.
- Пише textfile collector метрики у `${NODE_EXPORTER_TEXTFILE_DIR}/${RESTORE_SMOKE_METRICS_FILE}`:
  - `koha_restore_smoke_last_run_timestamp_seconds`
  - `koha_restore_smoke_last_success_timestamp_seconds`
  - `koha_restore_smoke_last_status`
- `--dry-run` не запускає restore smoke і не оновлює freshness metrics.

#### Manual execution
```bash
bash scripts/test-restore.sh --help
SERVER_ENV=prod bash scripts/test-restore.sh
SERVER_ENV=prod bash scripts/test-restore.sh --source /var/backups/koha/2026-04-25_01-30-00
SERVER_ENV=prod bash scripts/test-restore.sh --source /var/backups/koha/2026-04-25_01-30-00 --dry-run
```

### `scripts/restore.sh`

#### Бізнес-логіка
- Disaster recovery restore для Compose path.
- Перевіряє backup set (`SHA256SUMS`, SQL dump, tar.gz архіви), зупиняє stack, відновлює Koha config/data, готує MariaDB/Elasticsearch volumes, імпортує SQL.
- Після restore запускає infra + Koha, нормалізує `koha-conf.xml`, опційно виконує `koha-elasticsearch --rebuild` і post-restore verify.
- Перед destructive DB restore зупиняє `koha-worker-default`, `koha-worker-long-tasks` та `koha-es-indexer`; workers запускаються тільки після відновлення DB і live-config.
- Руйнівний сценарій: без `--dry-run` зупиняє stack і очищає bind-volume дані.

#### Manual execution
```bash
bash scripts/restore.sh --help
SERVER_ENV=prod bash scripts/restore.sh --source /srv/backups/koha/2026-04-25_01-30-00 --dry-run
SERVER_ENV=prod bash scripts/restore.sh --source /srv/backups/koha/2026-04-25_01-30-00 --yes
```

### `scripts/collect-docker-logs.sh`

#### Бізнес-логіка
- Інкрементально збирає `docker compose logs` для всіх сервісів.
- Пише централізовані логи в `${VOL_KOHA_LOGS}/centralized/docker` або `LOG_EXPORT_ROOT`.
- Зберігає state-файл `${VOL_KOHA_LOGS}/centralized/.docker_logs_since` або `LOG_STATE_FILE`.
- Підтримує `--since`, `--dry-run`, `--env dev|prod`.

#### Manual execution
```bash
SERVER_ENV=dev bash scripts/collect-docker-logs.sh --dry-run
bash scripts/collect-docker-logs.sh --env prod --since 2h
```

## Runtime helpers

### `scripts/lib/orchestrator-env.sh`

#### Бізнес-логіка
- Shared helper для Категорії 1б.
- Резолвить env у порядку: explicit `--env-file`, `ORCHESTRATOR_ENV_FILE`, local `.env` dev fallback.
- Парсить dotenv без `source`/eval і експортує ключі як environment variables.
- Fallback на `.env` призначений тільки для локального dev, не для CI/CD.

#### Manual execution
```bash
ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --list-modules
bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run
```

### `scripts/lib/docker-runtime.sh`

#### Бізнес-логіка
- Shared runtime adapter для команд всередині контейнерів.
- `docker_runtime_exec SERVICE ...` підтримує `DOCKER_RUNTIME_MODE=swarm|compose`.
- У Swarm mode шукає running task container за label `com.docker.swarm.service.name=${STACK_NAME}_${service}`.
- Якщо Swarm container/service не знайдено, робить fallback на `docker compose exec`; якщо контейнер знайдено, помилку команди не маскує.
- `docker_runtime_restart_service koha` у Swarm виконує `docker service update --force`, у Compose робить restart/up fallback.

#### Manual execution
```bash
DOCKER_RUNTIME_MODE=compose bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help
ORCHESTRATOR_MODE=swarm STACK_NAME=koha ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module verify --no-restart
```

## Runtime/out-of-scope

### `scripts/deploy-orchestrator.sh`

#### Бізнес-логіка
- Legacy Compose orchestrator.
- Нові CI/CD інтеграції йдуть через `deploy-orchestrator-swarm.sh`.

#### Manual execution
```bash
bash scripts/deploy-orchestrator.sh
```

### `scripts/install-collect-logs-timer.sh`

#### Бізнес-логіка
- Встановлює systemd service/timer для `collect-docker-logs.sh`.
- Копіює `systemd/koha-deploy-collect-logs.service` і `systemd/koha-deploy-collect-logs.timer` у `/etc/systemd/system`.
- Підтримує `--interval` для заміни `OnUnitActiveSec` у timer unit.
- Поточний unit-файл має бути синхронізований з autonomous env contract (`SERVER_ENV` або `ExecStart ... --env prod`) перед production install.
- Потребує host-level systemd/sudo контексту.

#### Manual execution
```bash
sudo bash scripts/install-collect-logs-timer.sh --interval 5min
sudo bash scripts/install-collect-logs-timer.sh --no-start
```

### `scripts/validate_sops_encrypted.py`

#### Бізнес-логіка
- Guard script для перевірки, що env-файли справді SOPS-encrypted.
- Використовується як pre-commit/CI safety check для `env.dev.enc` і `env.prod.enc`.

#### Manual execution
```bash
python3 scripts/validate_sops_encrypted.py env.dev.enc env.prod.enc
```

### Archived scripts

#### Бізнес-логіка
- `scripts/check-secrets-hygiene.sh` виведено зі scope, бо secret scanning виконує Gitleaks у CI.
- `scripts/test-smtp.sh` архівовано як ручний debug helper, не частина deploy/runbook contract.

## Non-destructive verification checklist

```bash
bash -n scripts/*.sh scripts/lib/*.sh scripts/patch/*.sh
bash scripts/check-ports-policy.sh
bash scripts/bootstrap-live-configs.sh --list-modules
bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run
bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help
ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh
bash scripts/restore.sh --help
bash scripts/collect-docker-logs.sh --help
```

### Manual SOPS smoke

```bash
ENV_TMP="$(mktemp /dev/shm/env-XXXXXX)"
chmod 600 "${ENV_TMP}"
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > "${ENV_TMP}"

ORCHESTRATOR_ENV_FILE="${ENV_TMP}" \
bash scripts/bootstrap-live-configs.sh --module csp-report-only --dry-run

shred -u "${ENV_TMP}" 2>/dev/null || rm -f "${ENV_TMP}"
```

### Elasticsearch indexer recovery after an outage

The indexer for the known Koha 26.05.05 daemon retains STOMP messages until
indexing finishes. When Elasticsearch reports `NoNodes`, it resets the job to
`new`, requeues the message and retries after five seconds with a fresh client.
An interrupted `started` job is processed again when RabbitMQ marks its message
as redelivered. Other indexing errors remain `failed` and require investigation.
Existing failed jobs are not retried automatically.

The versioned config is deployed with the normal Swarm deploy. At startup, the
service checks the original daemon's SHA-256; if it differs, the original daemon
runs and logs `Elasticsearch recovery patch is inactive`. Review the patch for
that Koha version before relying on recovery. RabbitMQ has no persistent data
volume in this stack, so replacing the broker can still lose queued messages.
Before restarting RabbitMQ, stop new jobs and drain its queues.

Check the indexer after deployment:

```bash
docker service logs --since 10m koha_koha-es-indexer 2>&1 | grep -E 'recovery patch is inactive|Elasticsearch unavailable|Update of elastic index failed'
```

No output means none of these messages appeared in the selected log interval;
it does not prove that outage recovery has been exercised.
