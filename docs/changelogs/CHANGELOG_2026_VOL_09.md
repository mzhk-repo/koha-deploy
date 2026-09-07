# CHANGELOG 2026 VOL 09

### 17) Live patch adapter: автодетекція Swarm та виправлення середовища виконання syspref модулів

- Контекст (2026-09-07):
  - під час запуску post-restore sysprefs модуль `search-prefs` завершувався з помилкою `service "koha" is not running`;
  - `DOCKER_RUNTIME_MODE` не експортувався у середовище дочірніх процесів патч-скриптів, через що `docker_runtime_mode` помилково переходив у Compose fallback замість Swarm;
  - у `patch-koha-sysprefs-opac-matomo.sh` виклик `cp -a` для тимчасового файлу `mktemp` завершувався з `Invalid argument`.

- Зміни:
  - `docker_runtime_mode()` тепер автоматично виявляє активний Docker Swarm і наявність сервісу стеку `${STACK_NAME:-koha}`, якщо змінна не задана явно;
  - `restore.sh`, `bootstrap-live-configs.sh` та `_patch_common.sh` явно експортують `DOCKER_RUNTIME_MODE`, `STACK_NAME` та `ORCHESTRATOR_MODE` у дочірні процеси;
  - `patch-koha-sysprefs-opac-matomo.sh` переведено на стандартний `cp` без збереження несумісних атрибутів файлу;
  - перевірено успішне виконання sysprefs модулів через Swarm exec (`koha-mysql` та cache flush).

- Перевірено:
  - `bash -n`, `shellcheck --severity=warning`, `git diff --check`;
  - пряме виконання sysprefs модулів проти Swarm стеку;
  - регресійні тести в `tests/*.test.sh`.

### 16) Swarm updates: оптимізація healthcheck timing та скорочення monitor duration

- Контекст (2026-09-07):
  - під час `docker service update` оновлення сервісу `koha` штучно затримувалося на 120 секунд через `update_config.monitor: 120s`;
  - `interval: 30s` у Swarm override змушував очікувати першого healthcheck до 30 секунд навіть після швидкого старту бекенду;
  - `start_period: 360s` був надлишковим для нормального старту Koha.

- Зміни:
  - у `docker-compose.swarm.yml` для `koha` зменшено `start_period` до `120s` (максимальний час холодного старту), інтервал перевірки здоров'я скорочено до `10s`, таймаут до `5s`;
  - час контролю стабільності після переходу в healthy (`update_config.monitor` та `rollback_config.monitor`) скорочено зі 120s до `15s` для `koha`, `koha-worker-default` та `koha-worker-long-tasks`;
  - у `docker-compose.yml` параметри healthcheck `koha` приведені у відповідність (`interval: 10s`, `start_period: 120s`, `retries: 3`);
  - застосовано оновлення параметрів до запущених сервісів у Swarm кластері.

- Перевірено:
  - `docker compose config` із `.env.example`;
  - `docker service update` для `koha_koha`, час збіжності після готовності скоротився зі 120 с до 10–15 с;
  - тести в `tests/*.test.sh`.

### 15) Restore workflow: паралельне масштабування стеку та синхронізація live configs

- Контекст (2026-09-07):
  - зупинка стеку у `scripts/restore.sh` тривала понад 6 хвилин через послідовне очікування масштабування 8 сервісів;
  - після розпакування бекапу `koha` не міг стартувати з помилкою `Access denied for user 'koha_db'`, оскільки архів `koha_config.tar.gz` перезаписував `koha-conf.xml` реквізитами DB та RabbitMQ з джерела бекапу (prod);
  - функція нормалізації викликала `chown` на хості без sudo, завершуючись із `Operation not permitted`;
  - сервіс `koha-es-indexer` зупинявся на старті, але не повертався до `scale 1`;
  - імпортовані sysprefs не синхронізувалися з цільовим середовищем після відновлення БД.

- Зміни:
  - у `scripts/lib/docker-runtime.sh` додано `docker_runtime_scale_services` для паралельного масштабування сервісів Swarm з `--detach` та швидкого завершення завислих контейнерів (`docker_runtime_wait_stack_containers_stopped`), що скоротило час зупинки з ~6.5 хвилин до ~15 секунд;
  - у `scripts/restore.sh` одразу після розпакування архіву конфігів викликається `bootstrap-live-configs.sh` (модулі `db`, `timezone`, `trusted-proxies`, `memcached`, `message-broker`, `smtp`) з поточного env-файлу цільового середовища;
  - нормалізацію прав `VOL_KOHA_CONF` переведено виключно у root-контейнер `alpine` з коректним `chown -R`;
  - у кроці запуску інфраструктури `es`, `rabbitmq`, `memcached` піднімаються паралельно, після старту Koha застосовуються системні налаштування (`search-prefs`, `domain-prefs`, `oidc-prefs`, тощо), запускаються воркери та повертається `koha-es-indexer`;
  - у `scripts/lib/autonomous-env.sh` додано експорт `AUTONOMOUS_ENV_TMP`;
  - додано regression test `tests/restore-parallel-scale-and-config-patch.test.sh`.

- Перевірено:
  - `bash -n`, `shellcheck --severity=warning`, `git diff --check`;
  - успішне проходження всіх регресійних тестів у `tests/`.

### 14) OIDC password lockdown: відновлення відсутніх syspref після deploy
  - post-deploy step `koha-lockdown-password-prefs.sh` завершував deploy з помилкою
    `OpacPasswordChange is not 0`;
  - у фактичній БД були відсутні `OpacPasswordChange` та `OpacResetPassword`;
  - скрипт використовував тільки `UPDATE`, тому не створював відсутні рядки й verify коректно виявляв
    незастосований lockdown.

- Зміни:
  - застосування переведено на атомарний idempotent `INSERT ... ON DUPLICATE KEY UPDATE` для обох
    preferences;
  - після зміни виконується Koha cache flush, щоб runtime одразу побачив lockdown;
  - додано regression test для обовʼязкового UPSERT і cache flush.

### 13) Elasticsearch indexer: self-healing `SearchEngine` preflight після host reboot

- Контекст (2026-08-27):
  - після перезапуску сервера `koha-es-indexer` входив у restart loop з exit code `11`;
  - фактична БД не містила `systempreferences.SearchEngine`, тому daemon обирав Zebra,
    виводив `Not using Elasticsearch` і падав на Elasticsearch-specific виклику;
  - попередній IaC-патч застосовувався лише в post-deploy bootstrap і не захищав звичайний restart host.

- Зміни:
  - indexer перед запуском daemon верифікує `SearchEngine` через `koha-mysql`;
  - коли значення відсутнє або відрізняється, виконується ідемпотентний SQL upsert до
    `KOHA_SEARCH_ENGINE` (default `Elasticsearch`) та cache flush;
  - daemon запускається лише після успішного підтвердження керованого значення;
  - `KOHA_SEARCH_ENGINE` явно передається до Swarm service.

### 12) Swarm deploy: повтор transient `update out of sequence`

- Контекст (2026-08-24):
  - migration deploy застосовує transition manifest, а потім фінальний stack manifest;
  - Swarm manager іноді повертав `update out of sequence` для `koha-es-indexer` під час другого
    `docker stack deploy`, через що CI завершувався, хоча помилка є transient optimistic update conflict.

- Зміни:
  - усі виклики `docker stack deploy` в оркестраторі проходять через обмежений retry wrapper;
  - повторюється лише точна помилка `update out of sequence`: за замовчуванням до 3 спроб із паузою 5 секунд;
  - інші помилки deploy не маскуються та одразу завершують виконання з помилкою;
  - додано параметри `ORCHESTRATOR_SWARM_DEPLOY_ATTEMPTS` і
    `ORCHESTRATOR_SWARM_DEPLOY_RETRY_DELAY_SECONDS`.

- Перевірено:
  - додано regression test для одного transient conflict і успішної повторної спроби;
  - `bash -n`, `shellcheck --severity=warning`, `git diff --check`.

### 11) Swarm deploy: readiness waits follow the current healthy task

- Контекст (2026-08-22):
  - post-deploy readiness перевіряв будь-який running container сервісу, зокрема task попередньої revision
    під час `start-first` update, а лог не показував фактичний час до готовності;
  - це не давало deployment-оркестратору точного критерію переходу до наступного кроку.

- Зміни:
  - `wait_for_swarm_container` визначає task з desired state `running`, звіряє його container і чекає
    `healthy` (або `running` для сервісів без healthcheck);
  - після першого успішного readiness check deploy одразу продовжується та фіксує elapsed time;
  - `ORCHESTRATOR_POST_DEPLOY_WAIT_TIMEOUT` лишається лише верхньою межею для несправного сервісу.
  - bootstrap порівнює content checksum керованих live config/CSP файлів і не робить force-restart `koha` та
    workers, якщо вони не змінилися; system preference modules застосовуються через один cache flush.

- Перевірено:
  - додано `tests/deploy-orchestrator-readiness.test.sh`: healthy current task завершує readiness без retry sleep.
  - додано `tests/bootstrap-live-configs-noop-restart.test.sh`: незмінний live config не викликає Docker restart.

### 10) STOMP cold start: відсутня RabbitMQ queue більше не блокує worker/indexer

- Контекст (2026-08-22):
  - після restart host `koha-worker-default` входив у restart loop, хоча consumer для
    `koha_library-default` був відсутній;
  - RabbitMQ Management API коректно повертає `404 Not Found` для queue, яку ще не створив жоден worker,
    але startup probe трактував цю відповідь як неуспішне очищення stale consumer.

- Зміни:
  - consumer probes для managed workers та `koha-es-indexer` трактують HTTP `404` як `0 consumers`;
  - інші відповіді Management API лишаються фатальними й тепер містять HTTP status/reason у помилці.

### 9) Elasticsearch indexer: singleton ownership і cleanup stale `elastic_index` consumers

- Контекст (2026-08-21):
  - діагностика показала один running `koha-es-indexer` task і відсутній legacy daemon у web, але два RabbitMQ
    consumers на `koha_library-elastic_index`;
  - inline supervisor вважав здоровим будь-який стан `consumers > 0`, тому stale connection не виявлявся.

- Зміни:
  - перед стартом daemon supervisor очищує stale connections, що споживають `elastic_index`, і чекає порожню queue;
  - monitor вимагає рівно одного consumer;
  - додано параметр `KOHA_ES_INDEXER_STALE_CONSUMER_CLEANUP` (default `true`).

### 8) STOMP workers: очищення stale RabbitMQ subscriptions перед стартом singleton task

- Контекст (2026-08-21):
  - після завершення worker task RabbitMQ міг зберігати його STOMP consumer без відповідного running Koha
    container; кожен replacement додавав новий consumer, тому обидві queues досягали `consumers=2`;
  - RabbitMQ channel/connection mapping підтвердив stale connections для `default` і `long_tasks`.

- Зміни:
  - supervisor через RabbitMQ Management API знаходить і закриває connections, що до старту вже споживають його
    exact queue, та чекає `consumers=0` перед запуском Perl worker;
  - додано керований параметр `KOHA_WORKER_STALE_CONSUMER_CLEANUP` (default `true`).

### 7) Worker isolation guard: Swarm task rotation не переходить у Compose fallback

- Контекст (2026-08-21):
  - під час `stop-first` worker update guard міг побачити старий task у попередній перевірці, а під час наступної
    перевірки контейнер уже був відсутній;
  - runtime adapter тоді помилково переходив до Compose exec, хоча runtime був Swarm.

- Зміни:
  - `docker_runtime_exec` у Swarm mode повертає помилку, а не переходить до Compose exec;
  - worker isolation guard повторює worker/consumer checks до `--wait-timeout`, якщо task ще не має running
    container, а потім повертає точну помилку.

### 6) STOMP workers: healthcheck більше не перериває supervisor до consumer grace period

- Контекст (2026-08-21):
  - RabbitMQ показував `consumers=2` для обох worker queues;
  - supervisor одразу записував `unhealthy`, тому Docker healthcheck завершував task через SIGTERM (`143`) раніше,
    ніж спливав `KOHA_WORKER_CONSUMER_GRACE_SECONDS`;
  - TERM запускав штатний довгий drain, унаслідок чого старий consumer перекривався з replacement task і
    restart loop самопідсилювався.

- Оновлено:
  - `scripts/container/koha-background-worker-supervisor.sh`;
  - `docs/ARCHITECTURE.md`.

- Зміни:
  - під час consumer grace period supervisor залишає health status `healthy`;
  - після завершення grace period supervisor сам виконує швидкий abort worker і завершує task, дозволяючи Swarm
    створити replacement без normal drain та дубльованого consumer.

- Перевірено:
  - локальні shell syntax/lint і rendered Compose manifest.

### 4) STOMP workers: усунено restart loop через відсутній `s6-setuidgid`

- Контекст (2026-08-20):
  - після виділення `koha-worker-default` і `koha-worker-long-tasks` в окремі Swarm services обидва tasks
    завершувались із кодом `127` одразу після pre-flight;
  - runtime image не містить `s6-setuidgid`, який supervisor використовував для запуску
    `background_jobs_worker.pl` від імені instance user.

- Оновлено:
  - `scripts/container/koha-background-worker-supervisor.sh`.

- Зміни:
  - запуск foreground worker переведено на наявний у Koha image `runuser --preserve-environment`;
  - збережено запуск від `${KOHA_INSTANCE}-koha` і успадкування `MAX_PROCESSES`.

- Перевірено:
  - Swarm logs обох worker services підтвердили root cause: `s6-setuidgid: command not found`;
  - локальні syntax/lint і rendered Compose manifest перевіряються перед наступним deploy.

### 5) STOMP workers: коректний drain і ізольований Swarm redeploy

- Контекст (2026-08-20):
  - supervisor зупиняв launcher `runuser`, а не дочірній Perl worker, тому під час drain worker лишався
    активним consumer і task міг чекати весь `stop_grace_period`;
  - операційне відновлення workers не повинно вимагати redeploy web, database або sidecar services.

- Оновлено:
  - `scripts/container/koha-background-worker-supervisor.sh`;
  - `scripts/deploy-orchestrator-swarm.sh`.

- Зміни:
  - Perl worker запускається через `setpriv` як прямий child supervisor, а не через проміжний `runuser`;
    drain призупиняє прийом нових jobs worker-процесом і чекає тільки його job children;
  - zombie Perl worker більше не вважається running: supervisor завершує task і дозволяє Swarm створити
    replacement замість зависання в `unhealthy`;
  - watchdog при неправильній кількості consumers завершує свій worker одразу, без long drain; це не дає
    Swarm накопичувати паралельні unhealthy tasks і створювати дубльовані STOMP consumers;
  - додано `ORCHESTRATOR_MODE=swarm-workers`: рендерить manifest лише для `koha-worker-default` і
    `koha-worker-long-tasks`, застосовує лише ці Swarm services та запускає їхній isolation guard.
  - workers-only rendering передає локальні placeholder names для не використаних worker services secrets,
    тому Compose не виводить хибні warnings про top-level secret interpolation.

### 1) STOMP background jobs: web і workers ізольовано у окремі Swarm services

- Контекст (2026-08-14):
  - healthcheck основного `koha` перезапускав web task, коли RabbitMQ consumer будь-якої обов'язкової queue зникав;
  - image одночасно запускав background workers setup-кроком і s6, що створювало дубльовані процеси з неоднозначним ownership.

- Оновлено:
  - `docker-compose.yml`, `docker-compose.swarm.yml`, `docker-compose.workers-transition.yml`;
  - `.env.example`;
  - `scripts/container/koha-worker-autostart-guard.sh`;
  - `scripts/container/koha-background-worker-supervisor.sh`;
  - `scripts/render-versioned-worker-configs.sh`;
  - `scripts/deploy-orchestrator-swarm.sh`;
  - `scripts/koha-background-workers-guard.sh`;
  - `scripts/bootstrap-live-configs.sh`, `scripts/restore.sh`.

- Зміни:
  - `koha` став web-only: healthcheck перевіряє лише intranet HTTP, а autostart guard fail-closed вимикає embedded workers;
  - додано singleton `koha-worker-default` і `koha-worker-long-tasks`: `replicas: 1`, `MAX_PROCESSES=1`, `stop-first`, queue-specific resources/drain timeout;
  - foreground supervisor вимагає `JobsNotificationMethod=STOMP`, виконує pre-flight live config/SQL/RabbitMQ/Koha connect і завершує лише свій task, якщо exact queue consumer не дорівнює одному понад 90 секунд;
  - guard і supervisor постачаються як versioned immutable Docker configs із content hash;
  - перший deploy із legacy workers виконується у дві фази, щоб не створити паралельних consumers; post-deploy guard вимагає нуль workers у web і по одному worker/consumer на кожній queue;
  - live config patches для DB/timezone/memcached/message broker окремо recycle workers; restore зупиняє workers/indexer перед DB restore і стартує workers після DB/config.

- Обмеження:
  - RabbitMQ persistence та STOMP TCP keepalive винесені в follow-up: поточний Koha `Net::Stomp` не передає `socket_options.keep_alive`, тому одних container sysctl недостатньо.

- Перевірено:
  - `bash -n` для змінених shell scripts;
  - `shellcheck --severity=warning` для змінених shell scripts;
  - `docker compose ... config` для normal і transitional Swarm manifests;
  - `git diff --check`.

### 2) CI/CD: виправлено Hadolint DL3066 через явне зазначення числових UID:GID

- Контекст (2026-08-20):
  - GitHub Actions CI (`shared-ci-cd.yml` Hadolint step) завершувався з exit code 1 через правило `DL3066: Non-numeric user-id may not be resolvable by host system`.

- Оновлено:
  - `memcached/Dockerfile`;
  - `elasticsearch/Dockerfile`;
  - `rabbitmq/Dockerfile`.

- Зміни:
  - у `memcached/Dockerfile` директиву `USER memcache` замінено на `USER 11211:11211`;
  - у `elasticsearch/Dockerfile` директиву `USER elasticsearch` замінено на `USER 1000:1000`;
  - у `rabbitmq/Dockerfile` директиву `USER rabbitmq` замінено на `USER 999:999`.

- Перевірено:
  - Hadolint `hadolint/hadolint:v2.15.1` для `memcached/Dockerfile`, `elasticsearch/Dockerfile`, `rabbitmq/Dockerfile` проходить без зауважень (exit code 0);
  - `docker build` успішно збирає локальні образи `test-memcached`, `test-es`, `test-rabbitmq`;
  - `git diff --check`.

### 3) Swarm deploy: виправлено валідацію `configs.*.mode` для `docker stack deploy`

- Контекст (2026-08-20):
  - `docker stack deploy` відхиляв згенерований Swarm manifest з помилкою `services.koha.configs.0.mode must be a number` через те, що `docker compose config` серіалізував octal mode як рядок (`"0555"`).

- Оновлено:
  - `docker-compose.yml`;
  - `scripts/deploy-orchestrator-swarm.sh`.

- Зміни:
  - у `docker-compose.yml` значення `mode` для configs переведено в числовий octal формат `0555`;
  - у `scripts/deploy-orchestrator-swarm.sh` додано нормалізацію `mode: "0555"` -> `mode: 0555` у пайплайні підготовки `DEPLOY_MANIFEST` (аналогічно нормалізації `cpus`).

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh`;
  - `shellcheck --severity=warning scripts/deploy-orchestrator-swarm.sh`;
  - валідація створення та прийняття тестового stack manifest із `mode: 0555` через `docker stack deploy`;
  - `git diff --check`.
