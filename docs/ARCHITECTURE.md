# Deploy Repo Architecture (Koha)

Дата оновлення: 2026-05-23

## 1) Призначення репозиторію

`koha-deploy` це operational/deploy репозиторій для production/dev Swarm-стеку Koha:
- оркестрація сервісів через `docker-compose.yml` і `docker-compose.swarm.yml`;
- керування runtime-параметрами через SOPS-encrypted `env.dev.enc` / `env.prod.enc` і `.env.example` як template;
- операційні скрипти для backup/restore, валідацій, Swarm deploy і live-патчів;
- CI/CD workflow з базовими перевірками і автодеплоєм через `scripts/deploy-orchestrator-swarm.sh`.

## 2) Поточний стек (фактичний)

Сервіси в `docker-compose.yml` + `docker-compose.swarm.yml`:
1. `koha` (зовнішній образ, рекомендовано digest pin у env)
2. `koha-es-indexer` (окремий crash-only daemon для Elasticsearch indexing)
3. `db` (`mariadb:11`)
4. `es` (локальна збірка з `elasticsearch/Dockerfile`)
5. `rabbitmq` (локальна збірка з `rabbitmq/Dockerfile`, STOMP enabled)
6. `memcached` (локальна збірка з `memcached/Dockerfile`)

Зовнішній доступ:
1. External Cloudflare Tunnel (окремий стек/інфраструктура)
2. Traefik gateway (`/home/pinokew/Traefik`)

Ключове:
- локальний сервіс `tunnel` видалено з `koha-deploy`;
- `koha` host-ports вимкнені; зовнішній доступ іде через `Cloudflare Tunnel -> Traefik -> Koha`;
- sidecar сервіси `es/rabbitmq/memcached` будуються локально у deploy-потоці;
- `koha-es-indexer` винесений з основного Koha container в окремий Swarm service з власними resource limits.

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

1. Основний service `koha` володіє вбудованими Koha background jobs workers для черг `default` і `long_tasks`.
2. Якщо `JobsNotificationMethod=STOMP`, healthcheck `koha` перевіряє не тільки intranet HTTP, а й RabbitMQ Management API consumers для `${memcached_namespace}-default` і `${memcached_namespace}-long_tasks`.
3. Якщо будь-яка обовʼязкова черга має `consumers=0`, `koha` стає unhealthy, а Swarm restart policy замінює task. Це покриває сценарій, коли `rabbitmq` перезапустився пізніше за `koha`, а живі worker-процеси втратили STOMP-підписку.
4. Якщо `JobsNotificationMethod` не дорівнює `STOMP`, RabbitMQ consumer check пропускається після успішної HTTP-перевірки.

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

Зовнішні bind-path томи задаються в `.env`:
1. `VOL_DB_PATH`
2. `VOL_ES_PATH`
3. `VOL_KOHA_CONF`
4. `VOL_KOHA_DATA`
5. `VOL_KOHA_LOGS`

## 8) Операційні скрипти

Основні скрипти:
1. `scripts/verify-env.sh` — валідація env-моделі.
2. `scripts/deploy-orchestrator-swarm.sh` — Swarm deploy: validation, volume init, versioned secrets, stack deploy, bootstrap і ES guard.
3. `scripts/bootstrap-live-configs.sh` — оркестрація live patch modules.
4. `scripts/koha-elasticsearch-index-guard.sh` — smart ES guard і перевірка RabbitMQ consumer для `koha-es-indexer`.
5. `scripts/backup.sh` — повний backup (DB + volumes + metadata/checksums).
6. `scripts/restore.sh` — restore/PITR-процедури.
7. `scripts/collect-docker-logs.sh` — централізований експорт docker logs.
8. `scripts/install-collect-logs-timer.sh` — плановий збір логів через systemd timer.

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
6. post-deploy `bootstrap-live-configs.sh`, `koha-elasticsearch-index-guard.sh`, password prefs lockdown
7. health/runtime checks для `koha` і `koha-es-indexer`

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
