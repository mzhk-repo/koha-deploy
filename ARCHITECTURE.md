# Deploy Repo Architecture (Koha)

Дата оновлення: 2026-03-03

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
6. `tunnel` (`cloudflared`, зовнішній доступ)

Ключове:
- `koha` host-ports вимкнені; зовнішній доступ іде через Cloudflare Tunnel.
- Sidecar сервіси `es/rabbitmq/memcached` будуються локально у deploy-потоці.

## 3) Мережева модель

1. Єдина docker-мережа: `kohanet`.
2. Міжсервісний доступ тільки внутрішніми DNS-іменами (`db`, `es`, `rabbitmq`, `memcached`).
3. Публічний трафік до Koha не відкривається напряму через host ports.

## 4) Конфігураційна модель

1. SSOT runtime-конфігів: `.env` + `.env.example` + `docker-compose.yaml`.
2. Live-конфіг Koha (`koha-conf.xml`) патчиться через модульні скрипти `scripts/patch/*`.
3. Оркестратор патчів: `scripts/bootstrap-live-configs.sh`.
4. Патч-флоу підтримує:
- первинний bootstrap чистого інстансу;
- selective rerun окремих модулів.

## 5) Дані і томи

Зовнішні bind-path томи задаються в `.env`:
1. `VOL_DB_PATH`
2. `VOL_ES_PATH`
3. `VOL_KOHA_CONF`
4. `VOL_KOHA_DATA`
5. `VOL_KOHA_LOGS`


## 6) Операційні скрипти

Основні скрипти:
1. `scripts/verify-env.sh` — валідація env-моделі.
2. `scripts/bootstrap-live-configs.sh` — оркестрація live patch modules.
3. `scripts/test-smtp.sh` — runtime SMTP тест.
4. `scripts/backup.sh` — повний backup (DB + volumes + metadata/checksums).
5. `scripts/restore.sh` — restore/PITR-процедури.
6. `scripts/collect-docker-logs.sh` — централізований експорт docker logs.
7. `scripts/install-collect-logs-timer.sh` + `systemd/*.service|*.timer` — плановий збір логів.

## 7) CI/CD архітектура

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

## 8) Правила і обмеження

1. Секрети не комітяться в git.
2. Постійні зміни робляться через deploy-репо (compose/env/scripts), а не ручними правками в контейнері.
3. Для backup/restore використовуються тільки `scripts/backup.sh` і `scripts/restore.sh`.
4. Зміни фіксуються в активному changelog-томі (`CHANGELOGS/`).

## 9) Структура репо (актуальна)

```text
koha-deploy/
  .github/workflows/ci-cd-checks.yml
  docker-compose.yaml
  .env.example
  scripts/
    backup.sh
    restore.sh
    verify-env.sh
    bootstrap-live-configs.sh
    test-smtp.sh
    patch/
      patch-koha-conf-xml-*.sh
  systemd/
    koha-deploy-collect-logs.service
    koha-deploy-collect-logs.timer
  CHANGELOG.md
  CHANGELOGS/
  NEW_CHAT_START_HERE.md
  ROADMAP_PROD.md
```
