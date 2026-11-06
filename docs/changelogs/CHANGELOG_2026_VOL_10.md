# CHANGELOG 2026 VOL 10

Продовження після досягнення `VOL_09` soft limit. Активний том для fail-safe змін deploy/runtime.

### 1) Koha schema safety: destructive automatic import заборонено на deploy-рівні

- Контекст (2026-09-07):
  - image-level `07-db-import.sh` трактував будь-яку помилку SQL probe як порожню БД і запускав
    `kohastructure.sql`, який містить destructive `DROP TABLE IF EXISTS`;
  - у Swarm `depends_on` не гарантує порядок старту, тому тимчасова недоступність DNS/DB під час reboot
    могла помилково активувати import для вже встановленої БД.

- Зміни:
  - `docker-compose.yml` і `docker-compose.swarm.yml` завжди додають `07-db-import.sh` до
    `KOHA_SETUP_SKIP_STEPS`, незалежно від значення з env; Swarm entrypoint повторно примусово додає skip
    після завантаження `app_env_payload`, тому runtime secret не може його скасувати; це захищає також
    старі опубліковані образи;
  - додано `scripts/koha-db-schema-guard.sh`: перед post-deploy patches він fail-closed перевіряє
    наявність непорожнього `systempreferences.Version` через фактичний Koha DB connection;
  - guard запускається перед `bootstrap-live-configs.sh`, тому помилка з'єднання, відсутня таблиця,
    порожній або відсутній `Version` не допускають syspref UPSERT;
  - `.env.example` і `docs/ARCHITECTURE.md` фіксують новий контракт: порожня БД ініціалізується тільки
    через Koha Web installer або штатний restore, після чого deploy запускається повторно;
  - додано regression test `tests/koha-db-import-safety.test.sh` для примусового skip і порядку guard.

- Перевірено:
  - `bash -n`, ShellCheck, regression tests, Compose/Swarm manifest rendering та `git diff --check`.

### 2) Swarm deploy: додано pre-pull образу Koha перед оновленням сервісів

- Контекст (2026-09-07):
  - при оновленні digest `KOHA_IMAGE` на новий образ Docker Swarm завантажував важкі шари (~2.6 GB)
    у фазі `Preparing` уже під час оновлення сервісу;
  - `wait_for_swarm_container` очікував запущеного контейнера з таймаутом 300s і завершувався з помилкою,
    якщо pull та extraction тривали довше за таймаут.

- Зміни:
  - у `scripts/deploy-orchestrator-swarm.sh` додано функцію `runtime_env_get_value` та процедуру `pre_pull_koha_image`:
    перед запуском `docker stack deploy` у режимах `swarm` та `swarm-workers` оркестратор перевіряє наявність
    `KOHA_IMAGE` локально (`docker image inspect`) і за потреби стягує його (`docker pull`) до початку оновлення сервісів;
  - додано регресійний тест `tests/deploy-orchestrator-pre-pull.test.sh`.

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh`;
  - `shellcheck --severity=warning scripts/deploy-orchestrator-swarm.sh`;
  - пройдено всі тести у `tests/*.sh`, включно з `tests/deploy-orchestrator-pre-pull.test.sh`;
  - `git diff --check`.

### 3) Koha sessions → Memcached: зафіксовано readonly baseline Ітерації 0

- Зафіксовано baseline у `docs/RUNBOOK_DR.md` перед будь-яким перемиканням
  backend сесій або очищенням таблиці:
  - `sessions`: `2,033,162` рядків і `data_length=475,004,928` bytes;
  - binlog position `mysql-bin.000009:2224172`, `ROW`, retention 7 днів;
  - raw binlog-файли за 2026-09-07—2026-09-12: `1,203,022,994` bytes;
  - Memcached: `curr_items=61`, `bytes=11,420`, `evictions=0`.
- Runtime deploy, restore, `TRUNCATE` і зміна grants не виконувалися.

### 4) Koha sessions → Memcached: додано bootstrap і fail-closed preflight

- Додано `KOHA_SESSION_STORAGE` до env-контракту (`mysql` за замовчуванням,
  `memcached` для rollout).
- Додано bootstrap-модуль `session-storage`, який для Memcached виконує
  set/get/delete roundtrip через `Koha::Caches`, ідемпотентно встановлює
  `SessionStorage` та перевіряє результат.
- Koha web у Compose/Swarm очікує доступний Memcached до `/init`, якщо вибрано
  `KOHA_SESSION_STORAGE=memcached`; таймаут preflight завершує старт з помилкою.
- Додано TCP healthcheck для Memcached і regression test
  `tests/koha-session-storage.test.sh`.
- Перевірено: `bash -n`, ShellCheck, усі `tests/*.sh`, env validation,
  Compose rendering і `git diff --check`. Runtime rollout не виконувався.

### 5) Koha sessions → Memcached: виправлено quoting bootstrap probe

- Після першого dev rollout `session-storage` падав із `sh: 1: Syntax error:
  "(" unexpected` під час передачі Perl probe через `koha-shell -c`.
- Probe і `SessionStorage` verification переведено на сумісний із `koha-shell`
  command quoting без вкладених shell-аргументів.
- Перевірено реальний set/get/delete probe у запущеному dev Koha-контейнері:
  `Memcached session probe ok`.

### 6) Koha sessions: healthcheck переведено на session-free public REST endpoint

- Koha healthcheck замінено з `HEAD /` на GET
  `/api/v1/public/libraries?_per_page=1`.
- `api-prefs` bootstrap тепер гарантує `RESTPublicAPI=1`, необхідний для
  доступу endpoint без login/session flow.
- Додано regression-перевірку endpoint і видалення старого `--spider`
  healthcheck-патерна.

### 7) Koha sessions: одноразове очищення після переходу на Memcached

- Після preflight `SessionStorage=memcached` і успішного Memcached roundtrip
  виконано `TRUNCATE TABLE sessions` у dev mirror.
- Результат: `sessions` зменшено з `2,033,351` до `0` рядків.
- Binlog підтверджує одну коротку Query-подію `TRUNCATE TABLE sessions`
  (`mysql-bin.000010:71744` → `71884`), без масиву DELETE-подій.
- Memcached залишився доступним, `evictions=0`; окремий cleanup timer не
  додавався.

### 8) MariaDB binlog purge та повний backup без PITR

- Контекст (2026-09-23):
  - на MariaDB 11.8 `slave_connections_needed_for_purge=1` за відсутності підключених реплік
    блокував автоматичне очищення старих binlog попри `DB_BINLOG_EXPIRE_DAYS=7`;
  - backup архівував усі наявні binlog, хоча PITR для цього стеку не використовується.

- Зміни:
  - у MariaDB Compose command встановлено `--slave-connections-needed-for-purge=0`;
  - з `backup.sh` вилучено PITR metadata та архівацію binlog; SQL dump, архіви томів,
    контрольні суми, retention та offsite copy збережено;
  - з `restore.sh` вилучено `--pitr-datetime` і відтворення binlog; старі повні backup set
    залишаються придатними для SQL restore;
  - оновлено env template, валідацію env та операційну документацію. RPO тепер
    обмежене частотою повних backup.

- Перевірено: `bash -n`, ShellCheck, Compose/Swarm rendering, `git diff --check`.
  Runtime deploy, purge binlog і restore не виконувалися.

### 9) Background STOMP consumer recovery: RabbitMQ keepalive та коротший watchdog

- Контекст (2026-10-05):
  - RabbitMQ STOMP listener не мав увімкненого TCP keepalive; причинний зв'язок із конкретними зависаннями ще не підтверджений;
  - watchdog-и опитували consumer кожні 30 секунд із grace period 90 секунд, а індексатор міг зависнути під час необмеженого очікування daemon після `TERM`.

- Зміни:
  - додано `rabbitmq/rabbitmq.conf` із `stomp.tcp_listen_options.keepalive = true`; config версіонується та підключається до RabbitMQ у Compose/Swarm;
  - тільки RabbitMQ service отримує sysctl `tcp_keepalive_time=30`, `tcp_keepalive_intvl=10`, `tcp_keepalive_probes=4`;
  - watchdog defaults індексатора і worker supervisor змінено на poll `10s` / grace `30s`; оновлено `.env.example`, encrypted `env.dev.enc` та `env.prod.enc`;
  - зовнішній `timeout 7` обмежує повний час RabbitMQ Management API probe індексатора й workers;
  - індексатор запускає Perl daemon напряму через `setpriv`; спільний process-control helper надсилає `TERM`, чекає до 10 секунд, потім надсилає `KILL` і повертає помилку;
  - додано behavior checks для consumer stable/recovery/failure transitions та daemon, що ігнорує `TERM`.

- Перевірено:
  - `bash -n`, ShellCheck (`--severity=warning`), `bash scripts/verify-env.sh --example-only`;
  - усі `tests/*.sh` пройшли, включно з новими watchdog/process checks;
  - Compose і Swarm manifests відрендерено; перевірено config mounts, RabbitMQ sysctls і значення watchdog `10/30` у rendered Swarm manifest;
  - зашифровані dev/prod env розшифровано лише у тимчасовий каталог із правами `0700/0600`, перевірено нові параметри та незмінність решти значень без їхнього виводу;
  - SOPS encryption validator і далі відхиляє наявне порожнє plaintext поле `KOHA_OPAC_PREFIX=`; воно також є у `HEAD` до цієї зміни.

- Runtime acceptance:
  - після dev redeploy служби RabbitMQ, індексатора та обох worker supervisors запущені `1/1`;
  - live RabbitMQ config повертає `stomp.tcp_listen_options.keepalive = true`, а sysctl контейнера RabbitMQ — `30/10/4`;
  - live env індексатора і supervisors має watchdog `10/30`; startup timeout збережено `300s`, worker drain — `300s` для `default` і `1800s` для `long_tasks`;
  - черги `elastic_index`, `default`, `long_tasks` мають по одному consumer і `0` ready/unacked повідомлень;
  - контрольовано закрито RabbitMQ-side TCP connections кожного з трьох consumers: кожен consumer повернувся рівно до одного, без зміни task; це перевіряє reconnect після явного broker close, але не silent TCP blackhole/keepalive detection;
  - однозаписний синтетичний MARCXML імпортовано в Koha та підтверджено документ Elasticsearch HTTP `200`; тестовий запис і документ прибрано;
  - тривалий активний `long_tasks` job і відтворення TCP blackhole не перевірені. Для першого потрібен більший синтетичний/анонімізований MARCXML; для другого — ізольований fault injection із мережевими правами, недоступними поточному runtime користувачу;
  - production deploy не виконувався. Перед RabbitMQ restart потрібно зупинити створення jobs, дочекатися активних jobs і перевірити порожні черги; постійного RabbitMQ data volume немає.

### 10) Production OIDC default library

- Changed `KOHA_IDP_DEFAULT_LIBRARY_ID` in the encrypted production configuration from `CPL` to `LDUBGD`, an existing production library.
- The production identity provider domain was absent; the next deploy must recreate it through the identity-provider bootstrap. No deploy or database changes were performed.
- Verified SOPS decryption and confirmed that this is the only changed plaintext configuration value.

### 11) Koha email queue startup prerequisites

- Normalize the image cron file to LF and create the instance lock directory with the configured Koha UID and GID before startup in Compose and Swarm.
- In production, enabled email for `library`, corrected the live cron file and lock directory, and changed `KohaAdminEmailAddress` from `root@localhost` to `noreply@ldubgd.edu.ua`.
- The queued WELCOME message reached SMTP before the sender correction and was rejected as `root@localhost`; it is now failed and was not retried. Delivery after the sender correction remains unverified.

### 12) Configure the Koha sender through env

- Added `KOHA_ADMIN_EMAIL_ADDRESS` to the env contract and set it in the encrypted dev and production configurations.
- The SMTP bootstrap validates the address, applies and verifies `KohaAdminEmailAddress`, and flushes the Koha cache. If the variable is absent, the existing preference is preserved.
- Checked shell syntax, ShellCheck, SOPS decryption and changed configuration keys; runtime bootstrap and delivery remain unverified.

### 13) Controlled Koha schema upgrade before Swarm deploy

- Added `scripts/koha-upgrade-schema-swarm.sh` for existing databases with Koha
  tasks on the local Swarm manager. It checks the configured target image and schema, refuses
  downgrades, waits for active RabbitMQ messages, stops Koha services, runs
  `koha-upgrade-schema`, and verifies the result. It does not require a backup.
- The normal Swarm deploy can run this step with the explicit
  `ORCHESTRATOR_SCHEMA_UPGRADE=true` flag; the default deploy remains unchanged.
  A failed or unverifiable migration retains a Swarm lock and stopped services.
- Documented the dev command, operational prerequisites and failure handling in
  `docs/scripts_runbook.md`. Production execution requires explicit approval.
- Verification: shell syntax, ShellCheck and mocked schema upgrade scenarios;
  a temporary container using the target image and DB network read the dev
  schema version and confirmed that Koha reports an update is needed.
  No live schema upgrade or deploy was performed.

### 14) RabbitMQ 4.4 native STOMP connection cleanup

- Prepared a derived RabbitMQ 4.4.0 Alpine image with a scoped Management API
  fix: when the existing connection record has no `pid`, use its `connection`
  process only if the protocol is STOMP. Existing API authorization and other
  protocol handling remain intact.
- Added optional `RABBITMQ_SWARM_IMAGE` to select a full image reference; when
  omitted, the existing official RabbitMQ image selection is unchanged. The
  derived image has not been published or deployed.
- Added an isolated integration check for three STOMP queues, Management API
  cleanup and replacement consumer delivery. Documented build and rollout
  prerequisites; no live RabbitMQ data or services were modified.

### 15) Dev Elasticsearch indexing recovery

- Jobs 391 and 394 failed with `BadResponse` / `NoNodes` while their biblio
  records 200 and 201 remained in MariaDB but were absent from Elasticsearch.
  Elasticsearch later responded from the indexer container and reported green.
- Reindexed only records 200 and 201 using Koha's `--bnumber` option; both
  Elasticsearch document requests returned HTTP 200. Restarted only the dev
  indexer service. Job 395 failed before the restart; control job 396 finished
  after it. The three RabbitMQ queues had one consumer each and no messages.
- Koha 26.05.05 wraps the original `NoNodes` exception as `BadResponse`, while
  the daemon checks only the original exception type. Its STOMP path also ACKs
  before committing a batch, so resetting jobs to `new` alone does not requeue
  their messages. The original transport failure remains undetermined and this
  runtime recovery does not provide a permanent fix.

### 16) Elasticsearch indexing retry after `NoNodes`

- Added a versioned copy of the Koha 26.05.05 indexer, selected only when the
  image daemon has the known SHA-256. It recognizes wrapped `NoNodes`, retains
  STOMP messages until the batch is processed, retries after an outage, and
  accepts redelivered jobs left `started` by an interrupted consumer.
- Versioned and mounted the daemon through the existing worker config renderer.
  A different upstream daemon runs unchanged with a warning; broker replacement
  can still lose queued messages because RabbitMQ has no persistent volume.
- Verified repeated `NoNodes`, later success and permanent error handling using
  mocked indexers in an isolated Koha container; checked Perl syntax, worker
  config rendering and Compose configuration. An isolated RabbitMQ 4.4 test
  verified individual ACK, requeue, redelivery headers and disconnect recovery.
  A live Elasticsearch outage has not been tested; no deployment was performed.
