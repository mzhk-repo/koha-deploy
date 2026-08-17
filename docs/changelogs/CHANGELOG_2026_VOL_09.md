# CHANGELOG 2026 VOL 09

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
