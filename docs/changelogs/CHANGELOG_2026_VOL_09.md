# CHANGELOG 2026 VOL 09

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
