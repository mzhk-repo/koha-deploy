# Deploy Repo Architecture (Koha)

Дата оновлення: 2026-08-21

## 1) Призначення репозиторію

`koha-deploy` це operational/deploy репозиторій для production/dev Swarm-стеку Koha:
- оркестрація сервісів через `docker-compose.yml` і `docker-compose.swarm.yml`;
- керування runtime-параметрами через SOPS-encrypted `env.dev.enc` / `env.prod.enc` і `.env.example` як template;
- операційні скрипти для backup/restore, валідацій, Swarm deploy і live-патчів;
- CI/CD workflow з базовими перевірками і автодеплоєм через `scripts/deploy-orchestrator-swarm.sh`.

## 2) Поточний стек (фактичний)

Сервіси в `docker-compose.yml` + `docker-compose.swarm.yml`:
1. `koha` (зовнішній образ, рекомендовано digest pin у env)
2. `koha-worker-default` (singleton STOMP consumer для `default`)
3. `koha-worker-long-tasks` (singleton STOMP consumer для `long_tasks`)
4. `koha-es-indexer` (окремий crash-only daemon для Elasticsearch indexing)
5. `db` (`mariadb:11`)
6. `es` (локальна збірка з `elasticsearch/Dockerfile`)
7. `rabbitmq` (локальна збірка з `rabbitmq/Dockerfile`, STOMP enabled)
8. `memcached` (локальна збірка з `memcached/Dockerfile`)

Зовнішній доступ:
1. External Cloudflare Tunnel (окремий стек/інфраструктура)
2. Traefik gateway (`/home/pinokew/Traefik`)

Ключове:
- локальний сервіс `tunnel` видалено з `koha-deploy`;
- `koha` host-ports вимкнені; зовнішній доступ іде через `Cloudflare Tunnel -> Traefik -> Koha`;
- sidecar сервіси `es/rabbitmq/memcached` будуються локально у deploy-потоці;
- `koha-es-indexer` винесений з основного Koha container в окремий Swarm service з власними resource limits.
- `koha-worker-default` і `koha-worker-long-tasks` мають лише внутрішню `kohanet`; вони не мають портів,
  `proxy-net` або `app_env_payload`.

## 3) Мережева модель

1. Внутрішня мережа Koha-стеку: `koha-deploy_kohanet`.
2. Зовнішня edge-мережа: `proxy-net` (на боці Traefik stack).
3. `koha` має dual-homing (`koha-deploy_kohanet` + `proxy-net`), де:
  - `kohanet` використовується тільки для внутрішніх sidecar-сервісів (`db`, `es`, `rabbitmq`, `memcached`);
  - `proxy-net` використовується тільки для north-south трафіку `Traefik -> koha`.
4. Traefik не підключається до `koha-deploy_kohanet`, щоб не мати мережевого доступу до внутрішніх сервісів Koha-стеку.
5. Міжсервісний доступ Koha sidecar-и залишають тільки внутрішні DNS-імена (`db`, `es`, `rabbitmq`, `memcached`).
6. Публічний трафік до Koha не відкривається напряму через host ports.

## 4) Elasticsearch indexing model

1. `koha-es-indexer` це окремий довгоживучий Swarm service, а не background-процес всередині `koha`.
2. Основний `koha` передає image-native `KOHA_ES_INDEXER_AUTOSTART=false`, що вимикає legacy
   `/usr/sbin/koha-es-indexer --start` і залишає черзі одного власника.
3. Перед стартом daemon сервіс чекає:
   - live `koha-conf.xml`;
   - SQL availability через `koha-mysql`;
   - Elasticsearch TCP availability;
   - RabbitMQ STOMP availability через TCP pre-flight і Koha-level `Koha::BackgroundJob->connect`.
4. Після readiness-перевірок supervisor запускає `es_indexer_daemon.pl` і контролює RabbitMQ consumer.
5. Модель recovery — crash-only: якщо Perl daemon завершується або consumer відсутній довше grace period,
   завершується контейнер, а restart виконує Compose/Swarm policy.
6. Перевірки через `ss` не використовуються, щоб не створювати orphan child processes.
7. Очікуваний runtime стан: один running Swarm task, один `runuser`, один `es_indexer_daemon.pl`, один RabbitMQ consumer на `koha_library-elastic_index`.
8. Swarm limits для сервісу задаються через `deploy.resources.limits`: memory `512m` за замовчуванням і CPU `0.50` за замовчуванням.

## 4.1) Background jobs model

1. `koha` є web-only service: `KOHA_BACKGROUND_WORKERS_AUTOSTART=false`, s6 user-services для workers
   видаляються перед `/init`, а immutable config-mounted guard fail-closed блокує image-native `--start` і `--restart`.
2. Healthcheck `koha` перевіряє тільки intranet HTTP. Втрата STOMP consumer не впливає на доступність OPAC/intranet.
3. Кожна черга має окремий singleton service: `koha-worker-default` або `koha-worker-long-tasks`, з
   `replicas: 1`, `MAX_PROCESSES=1`, update/rollback `stop-first` і `restart_policy.condition: any`.
4. Worker pre-flight перевіряє live config, instance user, SQL, RabbitMQ TCP і
   `Koha::BackgroundJob->connect`; startup завершується з помилкою, якщо `JobsNotificationMethod` не `STOMP`.
5. Foreground supervisor контролює exact queue `${memcached_namespace}-<queue>` через RabbitMQ Management API.
   Перед стартом він закриває stale RabbitMQ connections, що вже споживають його queue; для `stop-first`
   singleton service це єдиний безпечний спосіб прибрати залишені STOMP subscriptions після ротації task.
   Якщо consumer не дорівнює одному протягом 90 секунд, supervisor швидко завершує тільки worker task. Протягом
   цього grace period healthcheck лишається healthy, щоб Swarm не запустив normal drain до контрольованого abort.
   При штатному stop parent worker призупиняється, активному job надається queue-specific drain timeout
   (default 300 s, long_tasks 1800 s).
6. Web updates застосовуються `start-first` з rollback, workers — `stop-first`, щоб не створювати два consumers
   однієї черги. Перший migration deploy виконується у дві фази: web без embedded workers, потім workers.
7. RabbitMQ TCP keepalive і persistence не входять у цей change: поточний Koha `Net::Stomp` не вмикає
   `SO_KEEPALIVE`, тому container sysctl сам по собі не дає потрібного ефекту.

## 5) Конфігураційна модель

1. SSOT runtime-конфігів: SOPS `env.dev.enc` / `env.prod.enc`, `.env.example`, `docker-compose.yml` і `docker-compose.swarm.yml`.
2. Домени оркеструються як code через:
   - `KOHA_OPAC_SERVERNAME`
   - `KOHA_INTRANET_SERVERNAME`
3. Live-конфіг Koha (`koha-conf.xml`) патчиться через модульні скрипти `scripts/patch/*`.
4. Оркестратор патчів: `scripts/bootstrap-live-configs.sh`.

Актуальні модулі bootstrap:
- `timezone`
- `trusted-proxies`
- `memcached`
- `message-broker`
- `smtp`
- `domain-prefs`
- `identity-provider`
- `oidc-prefs`
- `verify`

## 6) Trusted proxy / real IP модель

Щоб не втрачати client IP у ланцюжку `Cloudflare -> Traefik -> Apache`:
1. У `koha` контейнері активується `mod_remoteip` на старті.
2. Монтується керований файл `apache/remoteip.conf`.
3. У `koha-conf.xml` патчиться `<koha_trusted_proxies>` через env `KOHA_TRUSTED_PROXIES`.

Результат:
- Apache access logs фіксують реальний IP клієнта (з `CF-Connecting-IP`), а не IP внутрішнього Traefik.

## 7) Дані і томи

Зовнішні bind-path томи задаються runtime env (SOPS `env.prod.enc` / `env.dev.enc` або explicit `ORCHESTRATOR_ENV_FILE`):
1. `VOL_DB_PATH`
2. `VOL_ES_PATH`
3. `VOL_KOHA_CONF`
4. `VOL_KOHA_DATA`
5. `VOL_KOHA_LOGS`

Deploy resolver визначає `VOL_DB_PATH` із відповідного SOPS env-файла: `env.prod.enc` для production та `env.dev.enc` для development. Production не має неявних fallback на `/tmp/env.decrypted` або `.env`.

Перед `init-volumes.sh` deploy перевіряє resolved `VOL_DB_PATH`. Для звичайного production redeploy каталог має містити `ibdata1` і `mysql/`; для усвідомленого першого запуску на новому сервері потрібно одноразово передати `ORCHESTRATOR_ALLOW_DB_INIT=true`.

## 8) Операційні скрипти

Основні скрипти:
1. `scripts/verify-env.sh` — валідація env-моделі.
2. `scripts/deploy-orchestrator-swarm.sh` — Swarm deploy: validation, volume init, versioned secrets/configs, двофазна worker migration, stack deploy, bootstrap і runtime guards.
3. `scripts/bootstrap-live-configs.sh` — оркестрація live patch modules.
4. `scripts/koha-elasticsearch-index-guard.sh` — smart ES guard і перевірка RabbitMQ consumer для `koha-es-indexer`.
5. `scripts/koha-background-workers-guard.sh` — post-deploy перевірка ізоляції web і рівно одного consumer для кожної worker queue.
6. `scripts/backup.sh` — повний backup (DB + volumes + metadata/checksums).
7. `scripts/restore.sh` — restore/PITR-процедури.
8. `scripts/collect-docker-logs.sh` — централізований експорт docker logs.
9. `scripts/install-collect-logs-timer.sh` — плановий збір логів через systemd timer.

## 9) CI/CD архітектура

Workflow: `.github/workflows/ci-cd-checks.yml`

`ci-checks` (fast-core):
1. Hadolint
2. Shellcheck
3. Compose validation
4. Trivy config scan
5. Env template validation
6. Secrets hygiene check
7. Internal ports policy check
8. Gitleaks

`cd-deploy` (тільки `push` у `main`):
1. SSH підключення до сервера (опційно через Tailscale `authkey`)
2. `git fetch/reset` до `origin/main`
3. SOPS decrypt runtime env у тимчасовий файл
4. `scripts/deploy-orchestrator-swarm.sh` у `ORCHESTRATOR_MODE=swarm`
5. `docker stack deploy` з rendered manifest
6. post-deploy `bootstrap-live-configs.sh`, worker isolation guard, `koha-elasticsearch-index-guard.sh`, password prefs lockdown
7. health/runtime checks для `koha`, обох workers і `koha-es-indexer`

## 10) Правила і обмеження

1. Секрети не комітяться в git.
2. Постійні зміни робляться через deploy-репо (compose/env/scripts), а не ручними правками в контейнері.
3. Для backup/restore використовуються тільки `scripts/backup.sh` і `scripts/restore.sh`.
4. Зміни фіксуються в активному changelog-томі (`docs/changelogs/`).

## 11) Структура репо (актуальна)

```text
koha-deploy/
  .github/workflows/ci-cd-checks.yml
  docker-compose.yml
  docker-compose.swarm.yml
  .env.example
  env.dev.enc
  env.prod.enc
  apache/
    remoteip.conf
  scripts/
    backup.sh
    restore.sh
    verify-env.sh
    deploy-orchestrator-swarm.sh
    bootstrap-live-configs.sh
    koha-elasticsearch-index-guard.sh
    patch/
      patch-koha-conf-xml-*.sh
      patch-koha-sysprefs-domain.sh
  systemd/
    koha-deploy-collect-logs.service
    koha-deploy-collect-logs.timer
  CHANGELOG.md
  docs/
    changelogs/
  AGENTS.md
  ROADMAP_PROD.md
```
