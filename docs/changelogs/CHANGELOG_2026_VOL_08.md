### 1) Deploy fix: повернено `app_env_payload` secret для основного Koha service

- Контекст:
  - після спрощення `koha-es-indexer` помилково зник `app_env_payload` secret mount у `koha_koha`;
  - `koha_koha` падав із `cannot open /run/secrets/app_env_payload` під час Swarm reconcile.

- Оновлено:
  - `docker-compose.swarm.yml`

- Зміни:
  - `app_env_payload` secret mount повернено тільки для основного `koha` service;
  - `koha-es-indexer` лишився без secret mount і читає runtime credentials через live `koha-conf.xml`.

- Перевірено:
  - redeploy з `env.dev.enc` завершився `Swarm deploy completed`;
  - `koha_koha` running;
  - `koha_koha-es-indexer` running, всередині працює `es_indexer_daemon.pl` під `library-koha`.

### 2) Elasticsearch guard: додано CLI-прапорець примусової переіндексації

- Оновлено:
  - `scripts/koha-elasticsearch-index-guard.sh`

- Зміни:
  - додано опцію `--reindex-force` для примусового повного `delete/rebuild` усіх Elasticsearch-записів;
  - прапорець використовує наявну безпечну гілку повної переіндексації, аналогічну `ORCHESTRATOR_ES_GUARD=force`.

### 3) Elasticsearch indexer: guard тепер перевіряє реальний RabbitMQ consumer після force reindex

- Контекст:
  - після `--reindex-force` сервіс `koha-es-indexer` міг бути `Running`, але не мати consumer на `koha_library-elastic_index`;
  - нові cataloguing jobs лишались у `background_jobs.status=new`, а ES count відставав від DB.

- Оновлено:
  - `docker-compose.yml`
  - `scripts/koha-elasticsearch-index-guard.sh`

- Зміни:
  - readiness `koha-es-indexer` перевіряє реальне Koha STOMP-підключення через `Koha::BackgroundJob->connect`, а не лише TCP-порт RabbitMQ;
  - guard після restart managed/legacy indexer чекає RabbitMQ consumer на `${memcached_namespace}-elastic_index` і падає з помилкою, якщо daemon не підписався на queue.

### 4) Elasticsearch indexer: додано watchdog STOMP-зʼєднання daemon

- Контекст:
  - після redeploy `koha-es-indexer` міг мати живий `es_indexer_daemon.pl`, але без активного STOMP-зʼєднання до RabbitMQ;
  - RabbitMQ показував `consumers=0` для `koha_library-elastic_index`, а нові `background_jobs` лишались у `new`.

- Оновлено:
  - `docker-compose.yml`
  - `docker-compose.swarm.yml`
  - `.env.example`

- Зміни:
  - `koha-es-indexer` тепер запускає `es_indexer_daemon.pl` через wrapper-watchdog;
  - watchdog перезапускає daemon, якщо STOMP-зʼєднання до RabbitMQ відсутнє довше `KOHA_ES_INDEXER_CONSUMER_GRACE_SECONDS`;
  - додано керовані параметри `KOHA_ES_INDEXER_MONITOR_INTERVAL` і `KOHA_ES_INDEXER_CONSUMER_GRACE_SECONDS`.

### 5) Elasticsearch indexer: замінено watchdog на crash-only foreground daemon

- Контекст:
  - watchdog перевіряв STOMP-зʼєднання через `ss`, але в контейнері `ss` недоступний або не показує потрібне зʼєднання;
  - перевірка постійно повертала false, watchdog стартував новий daemon, а старий Perl child міг лишатися живим;
  - у Swarm для `koha_koha-es-indexer` не було застосованого hard memory limit.

- Оновлено:
  - `docker-compose.yml`
  - `docker-compose.swarm.yml`
  - `.env.example`
  - `CHANGELOG.md`
  - `README.md`
  - `docs/scripts_runbook.md`

- Зміни:
  - прибрано watchdog-loop і `ss`-перевірку з `koha-es-indexer`;
  - `es_indexer_daemon.pl` запускається у foreground через `exec runuser`, тому завершення daemon завершує контейнер;
  - readiness лишив Koha-level STOMP connect через `Koha::BackgroundJob->connect`, а TCP pre-flight для Elasticsearch/RabbitMQ виконується через Bash `/dev/tcp`;
  - дефолтний memory limit indexer знижено до `512m`;
  - у Swarm додано `deploy.resources.limits` для `koha-es-indexer`.
