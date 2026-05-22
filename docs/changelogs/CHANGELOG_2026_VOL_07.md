### 25) Swarm deploy: виправлено причини `0/1` для Koha-adjacent сервісів

- Контекст:
  - `docker stack deploy` успішно створював `koha_db`, але `koha_koha`, `koha_es`, `koha_rabbitmq` і `koha_memcached` лишались `0/1`;
  - `koha_koha` відхилявся через відсутній bind source `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - `es`, `rabbitmq` і `memcached` відхилялись через локальні `koha-local-*` images у Swarm.

- Оновлено:
  - `.gitignore`
  - `scripts/init-volumes.sh`
  - `scripts/deploy-orchestrator-swarm.sh`
  - `docker-compose.swarm.yml`
  - `rabbitmq/enabled_plugins`

- Зміни:
  - `init-volumes.sh` тепер створює і нормалізує `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - Swarm timeout у deploy-orchestrator тепер друкує `docker service ps <service> --no-trunc`;
  - deploy-orchestrator перед `stack deploy` build-ить локальний image для `es` (`ORCHESTRATOR_SWARM_BUILD_SERVICES`, default: `es`), бо Elasticsearch потребує `analysis-icu`;
  - після `stack deploy` deploy-orchestrator виконує smart reconcile: `docker service update --force` запускається тільки для сервісів без running container, з rejected/failed task-ами або зі зміненим локально зібраним image;
  - ручний override лишився через `ORCHESTRATOR_SWARM_FORCE_UPDATE_SERVICES`; reconcile можна вимкнути через `ORCHESTRATOR_SWARM_RECONCILE=off` або примусити через `ORCHESTRATOR_SWARM_RECONCILE=force`;
  - cleanup deploy-orchestrator прибирає temp-файли `.koha.env.*`, `.koha.stack.raw.*.yml`, `.koha.stack.deploy.*.yml`;
  - `.gitignore` ігнорує temp env/manifest артефакти Swarm deploy;
  - `init-volumes.sh` додає ACL для поточного host runner на `${VOL_KOHA_CONF}`, щоб live config patch scripts могли читати й оновлювати `koha-conf.xml`, який створюється container user/group;
  - `rabbitmq` у Swarm переведено на офіційний `docker.io/rabbitmq:${RABBITMQ_VERSION:-3-management}`;
  - RabbitMQ plugins (`rabbitmq_management`, `rabbitmq_stomp`, `rabbitmq_web_stomp`) передаються через Docker Config;
  - `memcached` у Swarm переведено на офіційний `docker.io/memcached:${MEMCACHED_VERSION:-1.6}`.

- Перевірено:
  - `bash -n scripts/init-volumes.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `shellcheck scripts/init-volumes.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config` - OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` - OK.

### 26) Koha live config: додано патч DB credentials перед runtime verify

- Контекст:
  - після виправлення Swarm mount/image проблем `koha_koha` створював container, але health лишався `starting`;
  - логи Koha показували `Access denied for user 'koha_db'` і `Access refused for user 'koha_mq'`;
  - live `koha-conf.xml` у volume містив застарілі/default credentials, а bootstrap verify не перевіряв секретні поля.

- Оновлено:
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/patch/patch-koha-conf-xml-db.sh`
  - `scripts/patch/patch-koha-conf-xml-verify.sh`

- Зміни:
  - додано модуль `db`, який патчить основний DB block у `${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml` з env (`DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`);
  - `bootstrap-live-configs.sh` запускає `db` перед іншими live config модулями;
  - `patch-koha-conf-xml-verify.sh` тепер перевіряє DB connection block і secret-поля DB/RabbitMQ без виводу секретів у stdout або CLI args.

- Перевірено:
  - `bash -n scripts/bootstrap-live-configs.sh scripts/patch/patch-koha-conf-xml-db.sh scripts/patch/patch-koha-conf-xml-verify.sh` - OK;
  - `shellcheck scripts/bootstrap-live-configs.sh scripts/patch/patch-koha-conf-xml-db.sh scripts/patch/patch-koha-conf-xml-verify.sh` - OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` - OK;
  - `bash scripts/patch/patch-koha-conf-xml-db.sh --env-file .env.example --dry-run --no-wait` - OK;
  - `git diff --check` - OK.

- Runtime-перевірка:
  - live `koha-conf.xml` пропатчено з актуального Swarm secret payload без друку секретів;
  - `docker service update --force koha_koha` завершився convergence;
  - `koha_koha` перейшов у `1/1`, container health: `healthy`;
  - HTTP-перевірка всередині container: `wget -q --spider http://localhost:${KOHA_INTRANET_PORT:-8081}` - OK.

### 27) Swarm deploy: додано smart Elasticsearch index guard для Koha cataloguing

- Контекст:
  - після чистого/порожнього Elasticsearch volume Koha працювала з `SearchEngine=Elasticsearch`, але індекси `koha_library_biblios` і `koha_library_authorities` були відсутні;
  - `cataloguing/addbiblio.pl` падав з HTTP 500 до вставки запису в БД через `index_not_found_exception`.

- Оновлено:
  - `scripts/koha-elasticsearch-index-guard.sh`
  - `scripts/deploy-orchestrator-swarm.sh`
  - `.env.example`
  - `docs/scripts_runbook.md`

- Зміни:
  - додано окремий deploy-adjacent скрипт `koha-elasticsearch-index-guard.sh`;
  - orchestrator запускає guard після `bootstrap-live-configs.sh` і повторного очікування running `koha`, перед password lockdown;
  - guard пропускається, якщо `USE_ELASTICSEARCH=false` або Koha syspref `SearchEngine` не дорівнює `Elasticsearch`;
  - якщо індекси відсутні, виконується `koha-elasticsearch --rebuild --reset -v ${KOHA_INSTANCE}`;
  - якщо індекси існують, guard порівнює DB counts (`biblio`, `auth_header`) з ES `_count`;
  - default policy: `ORCHESTRATOR_ES_GUARD=smart`, `ORCHESTRATOR_ES_REINDEX_ON_MISMATCH=auto`, `ORCHESTRATOR_ES_MISMATCH_THRESHOLD_PERCENT=5`;
  - при суттєвому відставанні ES від DB запускається `koha-elasticsearch --rebuild -v ${KOHA_INSTANCE}`, при рівних counts reindex не виконується;
  - після guard-перевірок за замовчуванням виконується `koha-es-indexer --restart ${KOHA_INSTANCE}` (`ORCHESTRATOR_ES_INDEXER_RESTART=true`), щоб auto-indexing daemon перечитав актуальний `SearchEngine` після bootstrap.

- Перевірено:
  - `bash -n scripts/koha-elasticsearch-index-guard.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `shellcheck scripts/koha-elasticsearch-index-guard.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `scripts/koha-elasticsearch-index-guard.sh --help` - OK;
  - `ORCHESTRATOR_MODE=swarm DOCKER_RUNTIME_MODE=swarm STACK_NAME=koha scripts/koha-elasticsearch-index-guard.sh --env-file .env.example --dry-run --wait-timeout 30` - OK, dry-run визначив `DB=1, ES=0` для biblios і запланував reindex без виконання.
  - runtime diagnosis: `koha-es-indexer` до restart бачив stale Zebra context (`Not using Elasticsearch`, `Koha::SearchEngine::Zebra::Indexer`), після `koha-es-indexer --restart library` ES `koha_library_biblios` зріс з `0` до `2` при `biblio_count=2`.

### 28) Bootstrap: додано IaC-патч `SearchEngine=Elasticsearch`

- Контекст:
  - `USE_ELASTICSEARCH=true` був у env/config, але bootstrap не патчив Koha `systempreferences.SearchEngine`;
  - через це пошуковий рушій доводилось перемикати вручну в UI;
  - ручне перемикання після старту сервісів могло залишити `koha-es-indexer` у stale Zebra context.

- Оновлено:
  - `scripts/patch/patch-koha-sysprefs-search.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `.env.example`
  - `docs/scripts_runbook.md`

- Зміни:
  - додано bootstrap-модуль `search-prefs`;
  - модуль ставить `systempreferences.SearchEngine` з `KOHA_SEARCH_ENGINE` або автоматично з `USE_ELASTICSEARCH` (`true` -> `Elasticsearch`, false -> `Zebra`);
  - після direct SQL update виконується Koha cache flush через `Koha::Caches`;
  - `search-prefs` додано в `MODULE_ORDER` перед іншими DB/systempreferences патчами.

- Перевірено:
  - `bash -n scripts/patch/patch-koha-sysprefs-search.sh scripts/bootstrap-live-configs.sh scripts/koha-elasticsearch-index-guard.sh` - OK;
  - `shellcheck scripts/patch/patch-koha-sysprefs-search.sh scripts/bootstrap-live-configs.sh scripts/koha-elasticsearch-index-guard.sh` - OK;
  - `scripts/bootstrap-live-configs.sh --list-modules` показує `search-prefs`;
  - `ORCHESTRATOR_MODE=swarm DOCKER_RUNTIME_MODE=swarm STACK_NAME=koha scripts/bootstrap-live-configs.sh --env-file .env.example --module search-prefs --no-restart` - OK;
  - SQL і Koha Perl context бачать `SearchEngine=Elasticsearch`;
  - ES guard після патчу: `Biblios: DB=3, ES=3; OK`, `koha-es-indexer --restart library` - OK.

### 29) Bootstrap: додано IaC-патч `RESTBasicAuth`

- Контекст:
  - `RESTBasicAuth` має бути керованим через env/bootstrap, а не вручну в UI;
  - потрібен явний syspref-patch для стану "Увімкнено".

- Оновлено:
  - `scripts/patch/patch-koha-sysprefs-api.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `.env.example`
  - `docs/scripts_runbook.md`

- Зміни:
  - додано bootstrap-модуль `api-prefs`;
  - модуль ставить `systempreferences.RESTBasicAuth` з `KOHA_REST_BASIC_AUTH`;
  - default у `.env.example`: `KOHA_REST_BASIC_AUTH=1`;
  - після direct SQL update виконується Koha cache flush через `Koha::Caches`;
  - `api-prefs` додано в `MODULE_ORDER` після `search-prefs`.

- Перевірено:
  - `bash -n scripts/patch/patch-koha-sysprefs-api.sh scripts/bootstrap-live-configs.sh` - OK;
  - `shellcheck scripts/patch/patch-koha-sysprefs-api.sh scripts/bootstrap-live-configs.sh` - OK;
  - `scripts/bootstrap-live-configs.sh --list-modules` показує `api-prefs`;
  - `ORCHESTRATOR_MODE=swarm DOCKER_RUNTIME_MODE=swarm STACK_NAME=koha scripts/bootstrap-live-configs.sh --env-file .env.example --module api-prefs --no-restart` - OK;
  - runtime verify: `RESTBasicAuth=1`, Koha cache flush - OK.

### 30) Swarm deploy: додано versioned runtime env payload secret

- Контекст:
  - Docker secrets immutable, тому повторний deploy з тією самою назвою `app_env_payload` не гарантував підхоплення нових значень із `env.<env>.enc`;
  - потрібно, щоб новий env payload створював нову назву Docker secret, новий service spec і rolling update.

- Оновлено:
  - `scripts/render-versioned-env-secret.sh`
  - `scripts/deploy-orchestrator-swarm.sh`
  - `docs/scripts_runbook.md`

- Зміни:
  - додано `render-versioned-env-secret.sh`, який створює Docker secret з hash-based назвою payload;
  - `deploy-orchestrator-swarm.sh` запускає render secret після підготовки тимчасового env-файлу і до `docker compose config`;
  - `KOHA_APP_ENV_PAYLOAD_SECRET_NAME` дописується в тимчасовий env-файл перед render manifest;
  - `KOHA_APP_ENV_PAYLOAD_SECRET_NAME` виключено з hash/payload, щоб уникнути нескінченної зміни hash між деплоями.

### 31) Swarm deploy: додано versioned external secrets для DB/RabbitMQ

- Контекст:
  - `DB_PASS`, `DB_ROOT_PASS` і `RABBITMQ_PASS` у Swarm використовуються як окремі external Docker secrets;
  - Docker secrets immutable, тому зміна цих значень у `env.<env>.enc` також має створювати нову назву secret і новий service spec.

- Оновлено:
  - `scripts/render-versioned-env-secret.sh`
  - `docs/scripts_runbook.md`
  - `docs/scrypts_refactoring.md`

- Зміни:
  - `render-versioned-env-secret.sh` тепер створює versioned secrets для `DB_PASS`, `DB_ROOT_PASS`, `RABBITMQ_PASS`;
  - generated names дописуються в тимчасовий env-файл як `KOHA_DB_PASSWORD_SECRET_NAME`, `KOHA_DB_ROOT_PASSWORD_SECRET_NAME`, `RABBITMQ_PASSWORD_SECRET_NAME`;
  - generated `*_SECRET_NAME` виключено з env payload hash, щоб службові назви не спричиняли зайві rolling updates.

- Перевірено:
  - `bash -n scripts/render-versioned-env-secret.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `shellcheck scripts/render-versioned-env-secret.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` - OK;
  - `git diff --check` - OK;
  - real Docker smoke на копії `.env.example`: створено/перевикористано versioned secrets для env payload, DB password, DB root password і RabbitMQ password; усі generated names підставились у `docker compose config`.

### 32) Backup/restore: textfile collector metrics і restore smoke test

- Контекст:
  - monitoring stack очікує freshness metrics для Koha backup і безпечної перевірки restore;
  - dry-run не має оновлювати freshness timestamps, щоб не маскувати відсутність реального backup/restore.

- Оновлено:
  - `scripts/backup.sh`
  - `scripts/test-restore.sh`
  - `.env.example`
  - `docs/scripts_runbook.md`
  - `docs/RUNBOOK_DR.md`

- Зміни:
  - `backup.sh` пише `koha_backup.prom` у `${NODE_EXPORTER_TEXTFILE_DIR}` з метриками `koha_backup_last_run_timestamp_seconds`, `koha_backup_last_success_timestamp_seconds`, `koha_backup_last_status`;
  - додано окремий `scripts/test-restore.sh`, який імпортує SQL dump у тимчасовий MariaDB container і не змінює production Koha DB;
  - restore smoke пише `koha_restore_smoke.prom` з метриками `koha_restore_smoke_last_run_timestamp_seconds`, `koha_restore_smoke_last_success_timestamp_seconds`, `koha_restore_smoke_last_status`;
  - `.env.example` документує `NODE_EXPORTER_TEXTFILE_DIR=/data/node-exporter-textfile`, `BACKUP_METRICS_FILE=koha_backup.prom`, `RESTORE_SMOKE_METRICS_FILE=koha_restore_smoke.prom`;
  - `--dry-run` для backup і restore smoke не оновлює freshness metrics.

- Перевірено:
  - `bash -n scripts/backup.sh scripts/restore.sh scripts/test-restore.sh` - OK;
  - `shellcheck scripts/backup.sh scripts/test-restore.sh` - OK;
  - `bash scripts/test-restore.sh --help` - OK;
  - `SERVER_ENV=prod bash scripts/test-restore.sh --env prod` - OK, використано backup set `/data/backup/koha/2026-05-10_11-54-21`, SQL dump імпортовано у тимчасову MariaDB DB `koha_restore_smoke`, перевірено 277 таблиць;
  - textfile metrics створені на host: `/data/node-exporter-textfile/koha_backup.prom`, `/data/node-exporter-textfile/koha_restore_smoke.prom`, обидва status `1`.


### 33) Elasticsearch indexer: винесено daemon в окремий supervised сервіс

- Контекст:
  - `koha-es-indexer --status library` показував `ES indexing daemon not running`;
  - RabbitMQ черга `koha_library-elastic_index` мала повідомлення без consumer;
  - `SearchEngine=Elasticsearch`, індекси існували, але auto-indexing не обробляв queued jobs;
  - one-shot старт `koha-es-indexer` у Koha container міг падати до готовності RabbitMQ/ES/DNS і не мав Swarm/s6 supervision.

- Оновлено:
  - `docker-compose.yml`
  - `docker-compose.swarm.yml`
  - `.env.example`
  - `scripts/koha-elasticsearch-index-guard.sh`
  - `docs/scripts_runbook.md`

- Зміни:
  - додано окремий довгоживучий сервіс `koha-es-indexer`;
  - сервіс запускає `es_indexer_daemon.pl` у foreground через `runuser --preserve-environment` під `${KOHA_INSTANCE}-koha`;
  - перед стартом daemon чекає `koha-conf.xml`, DB, Elasticsearch і RabbitMQ STOMP;
  - додано `KOHA_ES_INDEXER_BATCH_SIZE` і `KOHA_ES_INDEXER_WAIT_TIMEOUT`;
  - ES guard перезапускає managed service `koha-es-indexer`, а legacy in-container daemon лишається fallback.

- Runtime-діагностика:
  - до ручного старту: `koha_library-elastic_index` мав `5` ready messages і `0` consumers;
  - після `koha-es-indexer --start library`: `koha_library-elastic_index` став `0` ready messages і `1` consumer.

### 34) Deploy fix: прибрано false-positive env keys з `koha-es-indexer` command

- Контекст:
  - `verify-env.sh` сканує `docker-compose.yml` на `${VAR}` і вимагає, щоб усі такі ключі були в `.env.example`;
  - inline shell нового `koha-es-indexer` сервісу містив runtime `${...}` expressions, які не є compose env keys;
  - deploy падав на missing keys: `deadline`, `es_host`, `KOHA_CONF`, `KOHA_HOME`, `label`, `PERL5LIB`, `SECONDS`.

- Оновлено:
  - `docker-compose.yml`

- Зміни:
  - runtime shell у `koha-es-indexer` переписано без `${...}` placeholders;
  - defaults для `KOHA_HOME` і `PERL5LIB` задано явно;
  - readiness checks для Elasticsearch/RabbitMQ виконуються через Perl `IO::Socket::INET` і `%ENV`, щоб не конфліктувати з compose env validation.

- Перевірено:
  - `bash scripts/verify-env.sh --example-only` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml config` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config` - OK;
  - `git diff --check -- docker-compose.yml` - OK.

### 35) Deploy fix: `koha-es-indexer` більше не залежить від Koha container user bootstrap

- Контекст:
  - Swarm update `koha_koha-es-indexer` падав з `task: non-zero exit (1)`;
  - логи task показали `read: arg count` через duplicated secret-entrypoint і `runuser: user library-koha does not exist`;
  - окремий container `koha-es-indexer` не проходить Koha setup pipeline основного container, тому instance user/group треба створювати ідемпотентно всередині самого сервісу.

- Оновлено:
  - `docker-compose.yml`
  - `docker-compose.swarm.yml`
  - `.env.example`

- Зміни:
  - прибрано окремий Swarm entrypoint і secret payload mount з `koha-es-indexer`;
  - daemon покладається на live `koha-conf.xml`, де DB/RabbitMQ credentials уже пропатчені bootstrap-модулями;
  - перед запуском `es_indexer_daemon.pl` сервіс ідемпотентно створює `${KOHA_INSTANCE}-koha` user/group з `KOHA_INSTANCE_UID`/`KOHA_INSTANCE_GID`;
  - додано default `KOHA_INSTANCE_UID=1000`, `KOHA_INSTANCE_GID=1000` у `.env.example`.

- Перевірено:
  - `bash scripts/verify-env.sh --example-only` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml config` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config` - OK;
  - `git diff --check -- docker-compose.yml docker-compose.swarm.yml .env.example docs/changelogs/CHANGELOG_2026_VOL_07.md` - OK.


