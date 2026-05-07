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
