# Deploy Repo Architecture (Koha)

Дата оновлення: 2026-03-13

## 1) Призначення репозиторію

`koha-deploy` це operational/deploy репозиторій для production-стеку Koha:
- оркестрація сервісів через `docker-compose.yaml`;
- керування runtime-параметрами через `.env` (SSOT);
- операційні скрипти для backup/restore, валідацій і live-патчів;
- CI/CD workflow з базовими перевірками і автодеплоєм на `main`.

## 2) Поточний стек (фактичний)

Сервіси в `docker-compose.yaml`:
1. `koha` (зовнішній образ, рекомендовано digest pin у `.env`)
2. `db` (`mariadb:11`)
3. `es` (локальна збірка з `elasticsearch/Dockerfile`)
4. `rabbitmq` (локальна збірка з `rabbitmq/Dockerfile`)
5. `memcached` (локальна збірка з `memcached/Dockerfile`)

Зовнішній доступ:
1. External Cloudflare Tunnel (окремий стек/інфраструктура)
2. Traefik gateway (`/home/pinokew/Traefik`)

Ключове:
- локальний сервіс `tunnel` видалено з `koha-deploy`;
- `koha` host-ports вимкнені; зовнішній доступ іде через `Cloudflare Tunnel -> Traefik -> Koha`;
- sidecar сервіси `es/rabbitmq/memcached` будуються локально у deploy-потоці.

## 3) Мережева модель

1. Внутрішня мережа Koha-стеку: `koha-deploy_kohanet`.
2. Зовнішня edge-мережа: `proxy-net` (на боці Traefik stack).
3. `koha` має dual-homing (`koha-deploy_kohanet` + `proxy-net`), де:
  - `kohanet` використовується тільки для внутрішніх sidecar-сервісів (`db`, `es`, `rabbitmq`, `memcached`);
  - `proxy-net` використовується тільки для north-south трафіку `Traefik -> koha`.
4. Traefik не підключається до `koha-deploy_kohanet`, щоб не мати мережевого доступу до внутрішніх сервісів Koha-стеку.
5. Міжсервісний доступ Koha sidecar-и залишають тільки внутрішні DNS-імена (`db`, `es`, `rabbitmq`, `memcached`).
6. Публічний трафік до Koha не відкривається напряму через host ports.

## 4) Конфігураційна модель

1. SSOT runtime-конфігів: `.env` + `.env.example` + `docker-compose.yaml`.
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
- `verify`

## 5) Trusted proxy / real IP модель

Щоб не втрачати client IP у ланцюжку `Cloudflare -> Traefik -> Apache`:
1. У `koha` контейнері активується `mod_remoteip` на старті.
2. Монтується керований файл `apache/remoteip.conf`.
3. У `koha-conf.xml` патчиться `<koha_trusted_proxies>` через env `KOHA_TRUSTED_PROXIES`.

Результат:
- Apache access logs фіксують реальний IP клієнта (з `CF-Connecting-IP`), а не IP внутрішнього Traefik.

## 6) Дані і томи

Зовнішні bind-path томи задаються в `.env`:
1. `VOL_DB_PATH`
2. `VOL_ES_PATH`
3. `VOL_KOHA_CONF`
4. `VOL_KOHA_DATA`
5. `VOL_KOHA_LOGS`

## 7) Операційні скрипти

Основні скрипти:
1. `scripts/verify-env.sh` — валідація env-моделі.
2. `scripts/bootstrap-live-configs.sh` — оркестрація live patch modules.
3. `scripts/test-smtp.sh` — runtime SMTP тест.
4. `scripts/backup.sh` — повний backup (DB + volumes + metadata/checksums).
5. `scripts/restore.sh` — restore/PITR-процедури.
6. `scripts/collect-docker-logs.sh` — централізований експорт docker logs.
7. `scripts/install-collect-logs-timer.sh` + `systemd/*.service|*.timer` — плановий збір логів.

## 8) CI/CD архітектура

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
3. `docker compose pull` для registry-сервісів
4. `docker compose build` для локальних sidecar образів
5. `docker compose up -d --remove-orphans`
6. `bootstrap-live-configs.sh`
7. health-check `koha`

## 9) Правила і обмеження

1. Секрети не комітяться в git.
2. Постійні зміни робляться через deploy-репо (compose/env/scripts), а не ручними правками в контейнері.
3. Для backup/restore використовуються тільки `scripts/backup.sh` і `scripts/restore.sh`.
4. Зміни фіксуються в активному changelog-томі (`CHANGELOGS/`).

## 10) Структура репо (актуальна)

```text
koha-deploy/
  .github/workflows/ci-cd-checks.yml
  docker-compose.yaml
  .env.example
  apache/
    remoteip.conf
  scripts/
    backup.sh
    restore.sh
    verify-env.sh
    bootstrap-live-configs.sh
    test-smtp.sh
    patch/
      patch-koha-conf-xml-*.sh
      patch-koha-sysprefs-domain.sh
  systemd/
    koha-deploy-collect-logs.service
    koha-deploy-collect-logs.timer
  CHANGELOG.md
  CHANGELOGS/
  AGENTS.md
  ROADMAP_PROD.md
```
