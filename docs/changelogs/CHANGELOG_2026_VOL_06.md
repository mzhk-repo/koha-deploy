## 2026-04-24

### 21) Scripts refactoring: оновлено preflight Категорії 1а для Swarm-оркестратора

- Контекст:
  - `scripts/check-secrets-hygiene.sh` виводиться зі scope, бо перевірку секретів виконує Gitleaks у CI;
  - репозиторій використовує `docker-compose.yml`, а частина 1а-перевірок очікувала `docker-compose.yaml`.

- Оновлено:
  - `scripts/check-ports-policy.sh`
  - `scripts/check-internal-ports-policy.sh`
  - `scripts/deploy-orchestrator-swarm.sh`

- Зміни:
  - прибрано виклик `check-secrets-hygiene.sh` з `check-ports-policy.sh`;
  - додано detection `docker-compose.yaml|docker-compose.yml` для port-policy preflight;
  - у `deploy-orchestrator-swarm.sh` додано `run_validation_scripts()` перед роботою з env-файлом і deploy-кроком;
  - fallback-повідомлення для локального `.env` уточнено як dev-only сценарій.

- Перевірено:
  - `bash -n scripts/check-ports-policy.sh scripts/check-internal-ports-policy.sh scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/check-ports-policy.sh` — OK;
  - `COMPOSE_FILE=docker-compose.yml bash scripts/verify-env.sh --example-only` — OK;
  - `bash scripts/check-internal-ports-policy.sh` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK.

### 22) Scripts refactoring: єдиний безпечний env-flow для Категорії 1б

- Контекст:
  - deploy-adjacent скрипти мають отримувати env з `ORCHESTRATOR_ENV_FILE` після CI/SOPS-розшифровки;
  - для локального dev збережено fallback на `.env`;
  - `source`/eval для env-файлів у 1б заборонено.

- Оновлено:
  - `scripts/lib/orchestrator-env.sh`
  - `scripts/init-volumes.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/koha-lockdown-password-prefs.sh`
  - `scripts/patch/_patch_common.sh`
  - `scripts/patch/patch-koha-sysprefs-domain.sh`
  - `scripts/patch/patch-koha-sysprefs-oidc.sh`
  - `scripts/patch/patch-koha-sysprefs-opac-matomo.sh`
  - `scripts/patch/patch-koha-identity-provider.sh`
  - `scripts/deploy-orchestrator-swarm.sh`

- Зміни:
  - додано спільний helper `orchestrator-env.sh`, який резолвить `--env-file` / `ORCHESTRATOR_ENV_FILE` / dev fallback `.env`;
  - env-файли читаються без `source`/eval, через безпечний dotenv-parser;
  - `init-volumes.sh`, `bootstrap-live-configs.sh`, `koha-lockdown-password-prefs.sh` приймають `--env-file`;
  - patch-модулі отримали спільний compose-file detection через `KOHA_COMPOSE_FILE`;
  - у Swarm-оркестратор підключено pre-deploy `init-volumes.sh` з `--env-file "${ENV_FILE}"`.

- Примітка:
  - `bootstrap-live-configs.sh` і `koha-lockdown-password-prefs.sh` env-сумісні з оркестратором, але не запускаються автоматично зі Swarm path на цьому кроці, бо частина модулів ще використовує `docker compose exec` і потребує окремого Swarm-native адаптера.

- Перевірено:
  - `bash -n` для змінених 1б shell-скриптів — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/patch/patch-koha-apache-csp-report-only.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `git diff --check` — OK.

### 23) Scripts refactoring: Swarm-native runtime adapter для patch/lockdown exec-команд

- Контекст:
  - частина 1б-скриптів виконувала DB/Koha команди через `docker compose exec`;
  - для Swarm path потрібен адаптер, який виконує команди у running task container за service label.

- Оновлено:
  - `scripts/lib/docker-runtime.sh`
  - `scripts/patch/_patch_common.sh`
  - `scripts/patch/patch-koha-sysprefs-domain.sh`
  - `scripts/patch/patch-koha-sysprefs-oidc.sh`
  - `scripts/patch/patch-koha-sysprefs-opac-matomo.sh`
  - `scripts/patch/patch-koha-identity-provider.sh`
  - `scripts/koha-lockdown-password-prefs.sh`

- Зміни:
  - додано `docker_runtime_exec SERVICE ...` з режимами `compose|swarm`;
  - default runtime: `ORCHESTRATOR_MODE=swarm` -> Swarm, інакше Compose;
  - Swarm mode шукає контейнер за label `com.docker.swarm.service.name=${STACK_NAME}_${service}`;
  - якщо Swarm container не знайдено, виконується fallback на `docker compose exec`;
  - якщо контейнер знайдено, помилка команди не маскується fallback-ом.

- Перевірено:
  - `bash -n` для runtime helper, patch-модулів і lockdown-скрипта — OK;
  - `bash scripts/patch/patch-koha-apache-csp-report-only.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-domain.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-opac-matomo.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-oidc.sh --env-file .env.example --apply --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - runtime mode resolver (`compose`, `swarm`, `ORCHESTRATOR_MODE=swarm`) — OK;
  - `git diff --check` — OK.

### 24) Scripts refactoring: підключено post-deploy bootstrap/lockdown у Swarm-оркестратор

- Контекст:
  - після появи `docker-runtime.sh` patch/lockdown скрипти можуть виконувати команди через Swarm task containers;
  - `deploy-orchestrator-swarm.sh` має запускати post-deploy конфігураційні кроки після `docker stack deploy`.

- Оновлено:
  - `scripts/deploy-orchestrator-swarm.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/lib/docker-runtime.sh`

- Зміни:
  - після `docker stack deploy` оркестратор чекає running containers для `${STACK_NAME}_db` і `${STACK_NAME}_koha`;
  - далі запускає `bootstrap-live-configs.sh --env-file "${ENV_FILE}"` у `ORCHESTRATOR_MODE=swarm` / `DOCKER_RUNTIME_MODE=swarm`;
  - після bootstrap/restart повторно чекає running `${STACK_NAME}_koha`;
  - потім запускає `koha-lockdown-password-prefs.sh --env-file "${ENV_FILE}"`;
  - `bootstrap-live-configs.sh` тепер рестартить `koha` через `docker_runtime_restart_service`;
  - для Swarm restart використовується `docker service update --force ${STACK_NAME}_koha`, з Compose fallback.

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh scripts/bootstrap-live-configs.sh scripts/lib/docker-runtime.sh scripts/koha-lockdown-password-prefs.sh` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - `git diff --check` — OK.

### 25) Scripts refactoring: автономний SOPS env-flow для Категорії 2

- Контекст:
  - автономні скрипти запускаються поза CI/CD і не отримують `ORCHESTRATOR_ENV_FILE`;
  - джерело середовища для cron/manual сценаріїв: CLI `--env dev|prod` або `SERVER_ENV`;
  - розшифрований env має жити у `/dev/shm`, а не в `/tmp`.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `scripts/backup.sh`
  - `scripts/restore.sh`
  - `scripts/collect-docker-logs.sh`

- Зміни:
  - додано helper `autonomous-env.sh` для `env.dev.enc` / `env.prod.enc`;
  - helper визначає середовище через перший positional `dev|prod`, `--env dev|prod`, `--env=dev|prod` або `SERVER_ENV`;
  - env розшифровується через `sops --decrypt --input-type dotenv --output-type dotenv` у `/dev/shm/env-*`, права `600`, cleanup через `trap`;
  - `backup.sh` і `restore.sh` мінімально змінені тільки навколо env-завантаження;
  - `restore.sh` і `collect-docker-logs.sh` отримали CLI `--env dev|prod`;
  - старий `source .env` прибрано з Категорії 2.

- Перевірено:
  - `bash -n scripts/lib/autonomous-env.sh scripts/backup.sh scripts/restore.sh scripts/collect-docker-logs.sh` — OK;
  - `bash scripts/restore.sh --help` — OK;
  - `bash scripts/collect-docker-logs.sh --help` — OK;
  - helper parsing/resolution для `--env prod`, `--env=dev`, positional `production`, `development`, `prod` — OK;
  - `sops` доступний як `/usr/bin/sops`;
  - decrypt-патерн узгоджено з `/opt/Dspace/DSpace-docker/scripts/lib/autonomous-env.sh` без явного `--age-key-file`;
  - `git diff --check` — OK.

### 26) Docs/scripts refactoring: синхронізовано autonomous decrypt-приклади з DSpace-патерном

- Контекст:
  - Koha helper Категорії 2 мав зайву прив'язку до `SOPS_AGE_KEY_FILE` / `${HOME}/.config/age/keys.txt`;
  - у DSpace успішний патерн використовує стандартний SOPS decrypt без явного `--age-key-file`.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `docs/scrypts_refactoring.md`
  - `docs/RUNBOOK_DR.md`
  - `docs/changelogs/CHANGELOG_2026_VOL_05.md`

- Зміни:
  - `decrypt_autonomous_env()` тепер використовує `sops --decrypt --input-type dotenv --output-type dotenv "${enc_file}"`;
  - temp-файл у `/dev/shm` приведено до DSpace-style `env-XXXXXX`;
  - roadmap/refactoring examples більше не радять `--age-key-file` або `/tmp` для тимчасового env;
  - DR runbook оновлено під `env.<env>.enc`, `SERVER_ENV=prod` і `--env prod`.

- Перевірено:
  - `bash -n scripts/lib/autonomous-env.sh` — OK;
  - `rg 'age-key|SOPS_AGE_KEY_FILE|/tmp/env' docs/scrypts_refactoring.md scripts/lib/autonomous-env.sh` — без застарілих прикладів;
  - `git diff --check` — OK.

### 27) Scripts refactoring: end-to-end non-destructive verification

- Контекст:
  - після рефакторингу Категорій 1а/1б/2 потрібна наскрізна перевірка без destructive дій.

- Перевірено:
  - `bash -n` для всіх shell-скриптів у `scripts/` — OK;
  - grep-перевірка: у 1б немає `source` / `. "$ENV_FILE"` для `ENV_FILE` або `ORCHESTRATOR_ENV_FILE` — OK;
  - grep-перевірка: прямі `docker compose exec` прибрані з patch/lockdown скриптів — OK;
  - `bash scripts/check-ports-policy.sh` — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/restore.sh --help` — OK;
  - `bash scripts/collect-docker-logs.sh --help` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - helper parsing/resolution для `--env prod`, `--env=dev`, positional `production`, `development`, `prod` — OK;
  - manual SOPS smoke: `sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > /dev/shm/env-*` + `ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module csp-report-only --dry-run` — OK;
  - tmp env cleanup через `shred -u ... || rm -f ...` — OK.

- Примітка:
  - `backup.sh`, `restore.sh`, `collect-docker-logs.sh` не запускались у runtime-режимі, бо вони можуть взаємодіяти з Docker/backup/restore state; перевірено тільки синтаксис, help і env helper parsing.

### 28) Docs: `scripts_runbook.md` приведено до Koha-specific стану

- Контекст:
  - `docs/scripts_runbook.md` містив залишки DSpace runbook після перенесення refactoring patterns у Koha deploy repo;
  - документація має відображати фактичні Koha scripts contracts після рефакторингу Категорій 1а/1б/2.

- Оновлено:
  - `docs/scripts_runbook.md`

- Зміни:
  - прибрано DSpace-specific секції та приклади (`backup-dspace`, `restore-backup`, maintenance/user-groups/runtime start);
  - додано Koha-specific опис validation, Swarm orchestrator, `init-volumes.sh`, `bootstrap-live-configs.sh`, lockdown і patch modules;
  - додано runtime helpers `orchestrator-env.sh`, `docker-runtime.sh`, `autonomous-env.sh`;
  - описано autonomous scripts `backup.sh`, `restore.sh`, `collect-docker-logs.sh`;
  - додано non-destructive verification checklist і manual SOPS smoke через `/dev/shm/env-XXXXXX`;
  - для `install-collect-logs-timer.sh` зафіксовано потребу синхронізувати systemd unit з autonomous env contract перед production install.

- Перевірено:
  - grep-перевірка на DSpace/legacy terms у `docs/scripts_runbook.md` — без збігів;
  - `git diff --check` — OK;
  - `git diff --no-index --check /dev/null docs/scripts_runbook.md` — OK;
  - `git diff --no-index --check /dev/null docs/changelogs/CHANGELOG_2026_VOL_05.md` — OK.

### 29) Category 2 autonomous scripts switched to Swarm runtime

- Контекст:
  - автономні scripts (`backup.sh`, `restore.sh`, `collect-docker-logs.sh`) мають працювати у production Swarm runtime за тим самим контрактом, що й Matomo/DSpace;
  - попередній default для cron/manual запуску лишався compose-oriented.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `scripts/lib/docker-runtime.sh`
  - `scripts/backup.sh`
  - `scripts/restore.sh`
  - `scripts/collect-docker-logs.sh`

- Зміни:
  - `autonomous-env.sh` переведено з прямого `source` decrypted dotenv на безпечний parser, щоб значення на кшталт IPv6/CIDR не виконувались як shell-код;
  - для Category 2 скриптів default runtime встановлено як `DOCKER_RUNTIME_MODE=swarm`, compose fallback лишився для local dev;
  - `backup.sh` виконує MariaDB dump/PITR metadata через `docker_runtime_exec db`; додано `--dry-run` без створення backup;
  - `restore.sh` виконує DB import, PITR, verify, service scale/reindex через runtime helper;
  - `collect-docker-logs.sh` збирає logs через `docker service logs` у Swarm mode.

- Перевірено:
  - `bash -n` і `shellcheck` для змінених Koha scripts/helper-ів — OK;
  - `backup.sh --env dev --dry-run` — OK;
  - `restore.sh --env dev --source <tmp-test-backup-set> --dry-run` — OK;
  - `collect-docker-logs.sh --env dev --since 1m --dry-run` завершився без запису state/output; Docker daemon повернув warnings для частини service logs через unavailable node/incomplete log stream.
========
---

## 2026-05-04

### 21) Backup offsite-копію переведено з host bind path на Rclone remote

- Контекст:
  - легка offsite-копія backup set більше не має залежати від змонтованої Google Drive папки на хості;
  - ціль offsite має задаватися через `rclone config`.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/backup.sh](/home/pinokew/Koha/koha-deploy/scripts/backup.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/verify-env.sh](/home/pinokew/Koha/koha-deploy/scripts/verify-env.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/docs/snippets/RUNBOOK_DR.md](/home/pinokew/Koha/koha-deploy/docs/snippets/RUNBOOK_DR.md)

- Зміни:
  - `BACKUP_OFFSITE_PATH` замінено на:
    - `BACKUP_RCLONE_REMOTE` - назва remote з `rclone config`;
    - `BACKUP_RCLONE_FOLDER` - папка всередині remote.
  - `scripts/backup.sh` тепер виконує lightweight offsite upload через `rclone copy`;
  - якщо `BACKUP_RCLONE_REMOTE` порожній, offsite-копія пропускається;
  - якщо `BACKUP_RCLONE_REMOTE` заданий, але `rclone` недоступний, backup завершується з явною помилкою;
  - `scripts/verify-env.sh` отримав fallback з `docker-compose.yaml` на фактичний `docker-compose.yml`;
  - локальний retention для `BACKUP_PATH` збережено, offsite retention для старого bind path прибрано.

- Перевірено:
  - `bash -n scripts/backup.sh` - OK;
  - `bash -n scripts/verify-env.sh` - OK;
  - `bash scripts/verify-env.sh` - OK (`.env` відсутній, перевірка автоматично перейшла в `--example-only`).

### 22) Swarm deploy orchestrator: гарантований cleanup тимчасових manifest-файлів

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/deploy-orchestrator-swarm.sh](/home/pinokew/Koha/koha-deploy/scripts/deploy-orchestrator-swarm.sh)

- Зміни:
  - cleanup винесено в окрему `cleanup`-функцію з глобальним `trap cleanup EXIT`;
  - тимчасові Swarm manifest-файли видаляються незалежно від результату завершення скрипта;
  - додано явне прибирання stale-файлів:
    - `.koha.stack.deploy.nvOviW.yml`;
    - `.koha.stack.raw.fYC8HY.yml`.

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh` - OK;
  - `shellcheck scripts/deploy-orchestrator-swarm.sh` - OK.

### 23) `init-volumes.sh`: додано ініціалізацію `BACKUP_PATH`

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/init-volumes.sh](/home/pinokew/Koha/koha-deploy/scripts/init-volumes.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)

- Зміни:
  - `BACKUP_PATH` додано до обов'язкових шляхів, які ініціалізує `init-volumes.sh`;
  - backup root нормалізується, проходить `guard_path`, створюється через той самий privileged strategy (`root`/`sudo`/Docker helper);
  - додано ownership/mode для backup root: `${BACKUP_UID}:${BACKUP_GID}` і `750`;
  - `BACKUP_UID`/`BACKUP_GID` додано як optional override у `.env.example`; за замовчуванням використовується UID/GID користувача, який запускає скрипт;
  - `--fix-existing` також нормалізує backup root (`dirs=750`, `files=640`).

- Перевірено:
  - `bash -n scripts/init-volumes.sh` - OK;
  - `shellcheck scripts/init-volumes.sh` - OK;
  - `bash scripts/verify-env.sh --example-only` - OK.

### 24) `backup.sh`: окремий rclone retention для Google Drive backup-копій

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/backup.sh](/home/pinokew/Koha/koha-deploy/scripts/backup.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/verify-env.sh](/home/pinokew/Koha/koha-deploy/scripts/verify-env.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/docs/RUNBOOK_DR.md](/home/pinokew/Koha/koha-deploy/docs/RUNBOOK_DR.md)
  - [/home/pinokew/Koha/koha-deploy/docs/scripts_runbook.md](/home/pinokew/Koha/koha-deploy/docs/scripts_runbook.md)

- Зміни:
  - додано `BACKUP_RCLONE_RETENTION_DAYS` як окремий retention для `BACKUP_RCLONE_REMOTE` / `BACKUP_RCLONE_FOLDER`;
  - локальний `BACKUP_RETENTION_DAYS` лишився окремим retention тільки для `BACKUP_PATH`;
  - remote retention за замовчуванням вимкнений (`0`), щоб не видаляти Google Drive backup-копії без явної конфігурації;
  - rclone retention видаляє тільки директорії backup set формату `YYYY-MM-DD_HH-MM-SS` через `rclone purge`.

- Перевірено:
  - `bash -n scripts/backup.sh scripts/verify-env.sh` - OK;
  - `shellcheck scripts/backup.sh scripts/verify-env.sh` - OK;
  - `bash scripts/verify-env.sh --example-only` - OK;
  - `bash scripts/backup.sh --env dev --dry-run` - OK (`BACKUP_RCLONE_RETENTION_DAYS=0`, remote retention disabled).

### 25) Swarm deploy: виправлено причини `0/1` для Koha-adjacent сервісів

- Контекст:
  - `docker stack deploy` успішно створював `koha_db`, але `koha_koha`, `koha_es`, `koha_rabbitmq` і `koha_memcached` лишались `0/1`;
  - `koha_koha` відхилявся через відсутній bind source `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - `es`, `rabbitmq` і `memcached` відхилялись через локальні `koha-local-*` images у Swarm.

- Оновлено:
  - `scripts/init-volumes.sh`
  - `scripts/deploy-orchestrator-swarm.sh`
  - `docker-compose.swarm.yml`
  - `rabbitmq/enabled_plugins`

- Зміни:
  - `init-volumes.sh` тепер створює і нормалізує `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - Swarm timeout у deploy-orchestrator тепер друкує `docker service ps <service> --no-trunc`;
  - deploy-orchestrator перед `stack deploy` build-ить локальний image для `es` (`ORCHESTRATOR_SWARM_BUILD_SERVICES`, default: `es`), бо Elasticsearch потребує `analysis-icu`;
  - `rabbitmq` у Swarm переведено на офіційний `docker.io/rabbitmq:${RABBITMQ_VERSION:-3-management}`;
  - RabbitMQ plugins (`rabbitmq_management`, `rabbitmq_stomp`, `rabbitmq_web_stomp`) передаються через Docker Config;
  - `memcached` у Swarm переведено на офіційний `docker.io/memcached:${MEMCACHED_VERSION:-1.6}`.

- Перевірено:
  - `bash -n scripts/init-volumes.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config` - OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` - OK.
