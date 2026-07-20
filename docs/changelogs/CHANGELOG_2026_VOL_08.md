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

### 6) Deploy validation: `verify-env.sh` більше не плутає runtime Bash-змінні з Compose env keys

- Контекст:
  - після переходу `koha-es-indexer` на `/dev/tcp` у inline Bash зʼявилась локальна runtime-змінна `$${endpoint...}`;
  - `scripts/verify-env.sh` шукав `${...}` напряму в compose-файлі й помилково вимагав `endpoint` у `.env.example`.

- Оновлено:
  - `scripts/verify-env.sh`
  - `docs/changelogs/CHANGELOG_2026_VOL_08.md`

- Зміни:
  - перед витягуванням Compose env keys валідатор ігнорує escaped runtime-послідовності `$${...}`;
  - `.env.example` не поповнюється службовими локальними Bash-змінними.

### 7) Swarm deploy: збережено string-тип для `deploy.resources.limits.cpus`

- Контекст:
  - `docker compose config` нормалізував `deploy.resources.limits.cpus` у число;
  - `docker stack deploy` відхиляв manifest з помилкою `services.koha-es-indexer.deploy.resources.limits.cpus must be a string`.

- Оновлено:
  - `scripts/deploy-orchestrator-swarm.sh`
  - `docs/changelogs/CHANGELOG_2026_VOL_08.md`

- Зміни:
  - перед `docker stack deploy` rendered manifest нормалізується так, щоб numeric `cpus:` значення були рядками.

- Перевірено:
  - `scripts/deploy-orchestrator-swarm.sh` з `env.dev.enc` завершився `Swarm deploy completed`;
  - `koha_koha-es-indexer` має Swarm limits `NanoCPUs=500000000`, `MemoryBytes=536870912`;
  - running container має 1 `runuser` і 1 `es_indexer_daemon.pl`, RAM близько 174 MiB із 512 MiB, PIDs=2;
  - service spec містить foreground `exec runuser ... es_indexer_daemon.pl`, без watchdog-loop і без `ss`.

### 8) Elasticsearch indexer: додано healthcheck для auto-recovery при відсутності STOMP-підписки

- Контекст (2026-05-23):
  - після redeploy `koha-es-indexer` повторно відтворив race condition: daemon стартував, але не встановив
    STOMP-підписку на `koha_library-elastic_index`; `consumers=0`, `messages=15` накопичилось за 14 год;
  - попереднє "crash-only foreground" рішення (запис 5) не покриває сценарій коли `es_indexer_daemon.pl`
    живий, але без активного TCP-зʼєднання до RabbitMQ — контейнер не падає, Swarm нічого не перезапускає;
  - тимчасовий ручний фікс: `docker service update --force koha_koha-es-indexer` → consumers=1, messages=0.

- Оновлено:
  - `docker-compose.yml`

- Зміни:
  - додано `healthcheck` до `koha-es-indexer`: перевіряє наявність ESTABLISHED TCP-зʼєднання до STOMP-порту
    (`MB_PORT`, default 61613) через `/proc/net/tcp` + `/proc/net/tcp6` (чиста ядерна FS, без credentials,
    без зовнішніх утиліт);
  - якщо зʼєднання відсутнє — healthcheck fail; після 3 невдач (90s) Swarm автоматично замінює task
    (`restart_policy: condition: any`);
  - `start_period: 360s` = `KOHA_ES_INDEXER_WAIT_TIMEOUT (300s) + 60s` буфер — хибні спрацювання під час
    нормального старту виключені;
  - при рестарті `koha-es-indexer` сайт і intranet залишаються доступними (немає зворотних залежностей).

- Перевірено:
  - YAML синтаксис валідний (`python3 yaml.safe_load`);
  - `scripts/verify-env.sh` проходить — `$${_p}` коректно ігнорується як runtime Bash-змінна;
  - жоден сервіс не має `depends_on: koha-es-indexer`.

### 9) Elasticsearch indexer: supervisor завершує контейнер при `consumers=0`

- Контекст (2026-05-27):
  - live-перевірка показала `koha_koha-es-indexer` у стані `healthy`, процес `es_indexer_daemon.pl` живий, але RabbitMQ queue `koha_library-elastic_index` мала `consumers=0` і накопичені `messages_ready`;
  - попередній healthcheck перевіряв лише ESTABLISHED TCP-зʼєднання до STOMP-порту, тому давав false positive: TCP socket існував, але daemon не був consumer черги;
  - Swarm restart policy надійно спрацьовує при exit контейнера, тому recovery має переводити втрату consumer у crash-only failure.

- Оновлено:
  - `docker-compose.yml`;
  - `docker-compose.swarm.yml`;
  - `.env.example`;
  - `README.md`;
  - `docs/scripts_runbook.md`.

- Зміни:
  - `koha-es-indexer` запускає `es_indexer_daemon.pl` під supervisor-loop замість прямого `exec`;
  - supervisor читає RabbitMQ Management API з credentials у live `koha-conf.xml` і перевіряє кількість consumer на `${memcached_namespace}-elastic_index`;
  - якщо `consumers=0` триває довше `KOHA_ES_INDEXER_CONSUMER_GRACE_SECONDS`, supervisor зупиняє daemon і завершує контейнер з кодом `1`;
  - додано керовані параметри `KOHA_ES_INDEXER_MONITOR_INTERVAL` і `KOHA_ES_INDEXER_CONSUMER_GRACE_SECONDS`.

- План runtime-перевірки:
  - застосувати оновлений Swarm manifest;
  - підтвердити, що при `consumers=0` supervisor завершує task;
  - підтвердити, що Swarm створює новий task і після старту RabbitMQ queue має `consumers>0`.

### 10) Koha background jobs: healthcheck контролює STOMP consumers для import queues

- Контекст (2026-06-25):
  - `koha-es-indexer` мав активний consumer на `koha_library-elastic_index`, тому Elasticsearch indexer не був root cause;
  - імпортні jobs `stage_marc_for_import` зависали в `background_jobs.status=new` у черзі `long_tasks`;
  - RabbitMQ показував `koha_library-long_tasks` з `messages_ready=1` і `consumers=0`;
  - ймовірний сценарій: `rabbitmq` task був перезапущений пізніше за `koha`, а вбудовані Koha background jobs workers лишились живі, але втратили STOMP consumer-підписку.

- Оновлено:
  - `docker-compose.yml`;
  - `docker-compose.swarm.yml`;
  - `docs/ARCHITECTURE.md`.

- Зміни:
  - healthcheck основного `koha` service лишив intranet HTTP-перевірку першим кроком;
  - якщо `JobsNotificationMethod` не дорівнює `STOMP`, RabbitMQ consumer check пропускається;
  - якщо `JobsNotificationMethod=STOMP`, healthcheck читає live `koha-conf.xml`, звертається до RabbitMQ Management API і перевіряє consumers для `${memcached_namespace}-default` та `${memcached_namespace}-long_tasks`;
  - якщо будь-яка обовʼязкова черга має `consumers=0`, `koha` стає unhealthy, щоб Swarm замінив task і перевідкрив worker STOMP-підписки;
  - у Swarm для `koha` встановлено production-friendly healthcheck timings: `start_period: 360s`, `interval: 30s`, `timeout: 10s`, `retries: 3`.

- План перевірки:
  - `python3 -c 'import yaml; yaml.safe_load(open("docker-compose.yml")); yaml.safe_load(open("docker-compose.swarm.yml"))'`;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config`;
  - `bash scripts/verify-env.sh --example-only`;
  - `git diff --check -- docker-compose.yml docker-compose.swarm.yml docs/ARCHITECTURE.md docs/changelogs/CHANGELOG_2026_VOL_08.md`;
  - після deploy перевірити `koha_library-default` і `koha_library-long_tasks`: очікувано `consumers>=1`.

### 11) Elasticsearch indexer: bootstrap відновлює відсутній `SearchEngine`

- Контекст (2026-07-06):
  - `koha-es-indexer` потрапив у restart loop з кодом `11`;
  - `es_indexer_daemon.pl` вибирав `Koha::SearchEngine::Zebra::Indexer` і падав на виклику
    `get_elasticsearch_params`, оскільки `systempreferences.SearchEngine` був відсутній;
  - модуль `search-prefs` виконував лише `UPDATE`, тому не створював видалений або відсутній рядок.

- Оновлено:
  - `scripts/patch/patch-koha-sysprefs-search.sh`.

- Зміни:
  - запис `SearchEngine` створюється або оновлюється через ідемпотентний
    `INSERT ... ON DUPLICATE KEY UPDATE`;
  - повторний bootstrap відновлює кероване значення без ручного SQL.

- Перевірка:
  - `bash -n scripts/patch/patch-koha-sysprefs-search.sh`;
  - `shellcheck scripts/patch/patch-koha-sysprefs-search.sh`;
  - `git diff --check -- scripts/patch/patch-koha-sysprefs-search.sh docs/changelogs/CHANGELOG_2026_VOL_08.md`.

### 12) Elasticsearch indexer: вимкнено дубльований legacy consumer у `koha`

- Контекст (2026-07-06):
  - після відновлення `SearchEngine=Elasticsearch` RabbitMQ показував два consumers на
    `koha_library-elastic_index`;
  - окремий `koha-es-indexer` service і legacy daemon усередині основного `koha` одночасно запускали
    `es_indexer_daemon.pl`;
  - legacy consumer міг маскувати втрату consumer керованого service.

- Оновлено:
  - `docker-compose.yml`;
  - `docker-compose.swarm.yml`;
  - `.env.example`;
  - `README.md`;
  - `docs/ARCHITECTURE.md`.

- Зміни:
  - додано image-native `KOHA_ES_INDEXER_AUTOSTART`, для deploy default `false`;
  - при `false` основний `koha` не запускає legacy indexer, а окремий service лишається єдиним
    власником `elastic_index` consumer;
  - Koha image зберігає backward-compatible default `true`, якщо прапорець не передано.

- Перевірено:
  - `docker compose --env-file .env.example -f docker-compose.yml config`;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config`;
  - `bash scripts/verify-env.sh --example-only`;
  - `git diff --check`.

### 13) Deploy resolution: додано автоматичне SOPS розшифрування env.prod.enc / env.dev.enc

- Контекст (2026-07-20):
  - під час деплою (включаючи GitHub Actions pipeline `.github/workflows/main.yml`), якщо `ORCHESTRATOR_ENV_FILE` не передано у скрипт, деплоєр робив fallback на порожній або дефолтний `.env`;
  - це призводило до того, що Swarm створював нову порожню базу даних для Koha замість підключення існуючого тому `/data2/volumes/koha-volumes/mysql_data` з `env.prod.enc`.

- Оновлено:
  - `scripts/lib/orchestrator-env.sh`;
  - `scripts/deploy-orchestrator-swarm.sh`.

- Зміни:
  - `deploy-orchestrator-swarm.sh` та `orchestrator-env.sh` тепер автоматично визначають цільове середовище (`production`/`development`, `prod`/`dev` або гілку `main`/`dev`);
  - при відсутності розшифрованого `ORCHESTRATOR_ENV_FILE` деплоєр автоматично розшифровує відповідний `env.prod.enc` або `env.dev.enc` через `sops` у тимчасову пам'ять `/dev/shm`;
  - після завершення деплою тимчасовий розшифрований файл безпечно видаляється (`shred`/`rm`).

