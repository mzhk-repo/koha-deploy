# CHANGELOG Volume 04 (2026)

Анотація:
- Контекст: новий активний том після досягнення hard limit у `CHANGELOG_2026_VOL_03.md`.
- Зміст: продовження робіт по CI/CD, CD-deploy та операційній стабілізації прод-оточення.

---

## 2026-03-03

### 1) Ротація changelog-томів (`VOL_03` -> archived, `VOL_04` -> active)

- Виконано ротацію за політикою лімітів:
  - `CHANGELOG_2026_VOL_03.md` досяг `363` рядків (вище `hard limit: 350`);
  - створено новий активний том:
    - [CHANGELOG_2026_VOL_04.md](/home/pinokew/Koha/koha-deploy/CHANGELOGS/CHANGELOG_2026_VOL_04.md)

- Оновлено індекс томів:
  - [CHANGELOG.md](/home/pinokew/Koha/koha-deploy/CHANGELOG.md)
  - `VOL_04` позначено як `active`;
  - попередній `VOL_03` переведено у статус `archived`.

### 2) Спрощення `.github/workflows/ci-cd-checks.yml` (fast core checks)

- Мета:
  - скоротити тривалість CI та зменшити складність workflow;
  - залишити тільки базові критичні перевірки + CD-деплой.

- Оновлено:
  - [.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)

- Зміни:
  - workflow скорочено з ~`438` до `178` рядків;
  - прибрано важкий job `build-and-publish` (buildx/trivy image scan/sbom/push);
  - `ci-checks` залишено у fast-core наборі:
    - `hadolint`
    - `shellcheck`
    - `docker compose config -q` (`.env.example`)
    - `verify-env --example-only`
    - `check-secrets-hygiene.sh`
    - `check-internal-ports-policy.sh`
    - `gitleaks`
  - `cd-deploy` збережено, але тепер залежить тільки від `ci-checks`;
  - deploy-поведінка лишилась стабільною:
    - pull для registry-сервісів;
    - build для локальних `koha-local-*` сервісів;
    - `up -d --remove-orphans` + bootstrap + health-check.

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` (через `rhysd/actionlint:1.7.8`) — OK.

### 3) Повернено `Trivy Config Scan` у fast-core CI

- За результатами ревізії спрощеного workflow повернуто базовий security gate:
  - `Trivy config` (тільки config scan, без image scan).

- Оновлено:
  - [.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)
  - додано:
    - env `TRIVY_IMAGE` (pinned digest);
    - крок `Trivy config scan` у `ci-checks`:
      - `trivy config --skip-check-update --exit-code 1 --severity HIGH,CRITICAL /work`

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` (через `rhysd/actionlint:1.7.8`) — OK.

### 4) Документація: перетворено `README.md` на комплексний операційний гайд

- **Мета:** створити всеобхідний, деталізований `README.md` за аналогією з `README.example.md`, адаптований під поточний Koha production-стек.

- **Обновлено:**
  - [README.md](/home/pinokew/Koha/koha-deploy/README.md) — повний переписаний документ

- **Структура нового README:**
  1. **Status section** — поточний статус, активні ініціативи, що закрито, відомі обмеження
  2. **About the project** — назначення, аудиторія, ключові можливості, скоп
  3. **Architecture stack** — таблиця технологій (Koha 24.x, MariaDB 11, ES 8.19.6, RabbitMQ 3, Memcached 1.6)
  4. **Repository topology** — детальна структура файлів та директорій (scripts/, patch/, systemd/, Dockerfiles, CI/CD)
  5. **System topology** — docker-compose arquitetura (сервіси, порти, health-checks, resource limits в таблицях)
  6. **Configuration model** — SSOT (.env, .env.example, compose), live-конфіг патчі, категорії змінних
  7. **Security** — security-first принципи (least privilege, no secrets in git, network isolation, Cloudflare Tunnel, container hardening)
  8. **Local environments** — передумови, підготовка, критичні змінні для local dev
  9. **Quick start** — step-by-step: стартувати сервіси, перевірити статус, застосувати конфіги, доступ з браузера
  10. **Operational procedures** — SMTP setup, backup/restore з прикладами, логування, автоматичний збір через systemd
  11. **Production deployment** — manual deploy procedure + GitHub Actions CI/CD workflow
  12. **CI/CD Architecture** — workflow stages, security gates, branch protection, artifact pinning
  13. **Monitoring & Alerts** — вбудовані health-checks (таблиця), рекомендовані метрики/SLO, централізований лог-збір
  14. **Troubleshooting** — типові проблеми (Koha не стартує, DB connection errors, ES issues, Tunnel connectivity, disk space)
  15. **References** — для нової сесії (AGENTS.md, ROADMAP_PROD.md, ARCHITECTURE.md), операцій (RUNBOOK_DR.md), зовнішні links

- **Перевірено:**
  - Усі посилання на файли перевірені і відповідають реальній структурі
  - Команди (docker compose, scripts/) актуальні
  - SMTP, backup/restore, CI/CD приклади відповідають факту
  - Status таблиця синхронізована з ROADMAP_PROD.md і CHANGELOG_2026_VOL_04.md
  - Структура i formatting (markdown, таблиці, code blocks) перевірена

- **Результат:**
  - README.md тепер готовий як **вичерпна операційна документація** для:
    - нових девелоперів (quick start guide);
    - операційної команди (procedures, monitoring, troubleshooting);
    - архітекторів (architecture, security, design decisions);
    - інтеграторів (API, integrations, customization points).

---

## 2026-03-11

### 5) Додано `paths-ignore` фільтр у CI/CD workflow для пропуску документації

- **Мета:** зменшити bezvýrod CI-виконань при оновленні документації та конфіг-шаблонів, які не впливають на runtime-стек.

- **Оновлено:**
  - [.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)

- **Зміни:**
  - додано `paths-ignore` фільтр до обох `pull_request` та `push` тригерів:
    ```yaml
    paths-ignore:
      - '**.md'              # Усі markdown файли (README.md, ROADMAP_PROD.md, ARCHITECTURE.md, CHANGELOG*, etc.)
      - '.env.example'       # Конфіг-шаблон (не впливає на runtime)
      - '.gitignore'         # Git-конфіг
      - 'archive/**'         # Архівовані файли
    ```

- **Поведінка:**
  - При push/PR з **тільки** текстовими змінами (всі файли в `paths-ignore`) → workflow **пропускається** (не запускаються jobs)
  - При push/PR зі змінами в **code/config** (scripts/, docker-compose.yaml, Dockerfiles, etc.) → workflow executes нормально
  - `workflow_dispatch` завжди запускається (manual trigger)

- **Перевірено:**
  - YAML syntax перевірена (valid GitHub Actions workflow)
  - Фільтри протестовані з `**.md` pattern (рекурсивно всі .md)
  - Логіка: якщо commit містить **хоча б одну** змінену файл НЕ в `paths-ignore`, то workflow запуститься

---

## 2026-03-13

### 6) Ітеративна міграція edge-доступу: `Cloudflare tunnel (koha-deploy)` -> `Traefik gateway`

- **Контекст / ціль:**
  - перейти з локального `tunnel` сервісу в `koha-deploy` на схему `Cloudflare Tunnel (external) -> Traefik -> Koha`;
  - підключити Traefik до `koha-deploy_kohanet`;
  - перевести домени OPAC/Staff у config-as-code;
  - закрити ризик втрати реального client IP у ланцюжку з двома проксі.

#### Ітерація 1: Traefik <-> Koha network gateway

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)
  - [/home/pinokew/Traefik/docker-compose.yml](/home/pinokew/Traefik/docker-compose.yml)

- Зміни:
  - для `kohanet` зафіксовано стабільне ім'я: `koha-deploy_kohanet`;
  - `traefik` підключено до зовнішньої мережі `koha-deploy_kohanet` (як gateway);
  - на сервісі `koha` додано Traefik labels для двох host-based роутерів:
    - OPAC: `library.pinokew.buzz`
    - Staff: `koha.pinokew.buzz`
  - backend порти в labels переведено на env-driven значення:
    - `${KOHA_OPAC_PORT}` / `${KOHA_INTRANET_PORT}`.

- Перевірено:
  - `docker compose config` для обох стеків — OK;
  - `docker inspect traefik` -> мережі: `proxy-net`, `koha-deploy_kohanet`;
  - після виходу `koha` у `healthy` обидва host-и повертають `HTTP/1.1 200 OK` через Traefik.

#### Ітерація 2: видалення локального tunnel сервісу з koha-deploy

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)

- Зміни:
  - видалено сервіс `tunnel` (cloudflared) зі стеку `koha-deploy`;
  - external access policy в compose-коментарях оновлено під edge gateway модель.

- Перевірено:
  - `docker compose up -d --remove-orphans` видалив `koha-deploy-tunnel-1`;
  - core services (`db/es/rabbitmq/memcached/koha`) залишились у робочому стані;
  - `koha` після перезапуску -> `healthy`.

#### Ітерація 3: домени як code (без ручних правок через UI)

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-domain.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-domain.sh)

- Зміни:
  - встановлено цільові домени в env SSOT:
    - `KOHA_OPAC_SERVERNAME=library.pinokew.buzz`
    - `KOHA_INTRANET_SERVERNAME=koha.pinokew.buzz`
    - `TRAEFIK_OPAC_HOST=library.pinokew.buzz`
    - `TRAEFIK_STAFF_HOST=koha.pinokew.buzz`
    - `KOHA_DOMAIN=pinokew.buzz`
  - додано bootstrap-модуль `domain-prefs`, який оновлює `systempreferences`:
    - `OPACBaseURL`
    - `staffClientBaseURL`.
  - усунуто дефект оркестратора: restart `koha` тепер виконується з абсолютними шляхами (`-f docker-compose.yaml --env-file ...`), незалежно від cwd.

- Перевірено (data/services):
  - `bash scripts/verify-env.sh` — OK;
  - `bootstrap-live-configs --modules domain-prefs` — OK;
  - БД `systempreferences`:
    - `OPACBaseURL=https://library.pinokew.buzz/`
    - `staffClientBaseURL=https://koha.pinokew.buzz/`.

#### Ітерація 4: real client IP за ланцюжком Cloudflare -> Traefik -> Apache

- Проблема підтверджена:
  - до фікса Apache access log фіксував IP Traefik (`172.19.x.x`) замість клієнтського.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/apache/remoteip.conf](/home/pinokew/Koha/koha-deploy/apache/remoteip.conf)
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-trusted-proxies.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-trusted-proxies.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-verify.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-verify.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - додано managed Apache конфіг `remoteip.conf` (mount у `conf-enabled`);
  - `koha` стартує через `sh -lc "a2enmod remoteip ...; exec /init"` (idempotent enable on each start);
  - додано env-параметр `KOHA_TRUSTED_PROXIES` + модуль `trusted-proxies` для `koha-conf.xml`;
  - verify-модуль розширено перевіркою `<koha_trusted_proxies>`.

- Перевірено (health/services/data):
  - `apache2ctl -M` -> `remoteip_module (shared)`;
  - `koha-conf.xml` містить `<koha_trusted_proxies>...` (sync з `.env`);
  - функціональний тест: запит через Traefik з `CF-Connecting-IP: 198.51.100.77` -> у `/var/log/koha/apache/other_vhosts_access.log` зафіксовано `198.51.100.77`;
  - OPAC + Staff через Traefik (`Host: library.pinokew.buzz` / `Host: koha.pinokew.buzz`) -> `HTTP 200` після `koha` health=healthy.

- Додаткове operational спостереження:
  - під час швидких `koha` recreate можливе тимчасове `404` від Traefik поки backend у `health: starting`; після переходу в `healthy` роутинг відновлюється (`200`).

### 7) Спрощення SSOT для доменів: прибрано дублюючі `TRAEFIK_*` змінні

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-domain.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-domain.sh)

- Зміни:
  - видалено:
    - `TRAEFIK_OPAC_HOST`
    - `TRAEFIK_STAFF_HOST`
  - Traefik labels тепер читають напряму:
    - `KOHA_OPAC_SERVERNAME`
    - `KOHA_INTRANET_SERVERNAME`
  - `patch-koha-sysprefs-domain.sh` тепер теж використовує тільки `KOHA_*_SERVERNAME` як єдине джерело істини.

- Перевірено:
  - `verify-env.sh` — OK;
  - `docker compose config` — OK;
  - `bootstrap-live-configs.sh --modules domain-prefs` — OK;
  - `systempreferences` залишились коректними:
    - `OPACBaseURL=https://library.pinokew.buzz/`
    - `staffClientBaseURL=https://koha.pinokew.buzz/`.

### 8) Документація синхронізована з фактичною Traefik-edge архітектурою

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/README.md](/home/pinokew/Koha/koha-deploy/README.md)
  - [/home/pinokew/Koha/koha-deploy/ARCHITECTURE.md](/home/pinokew/Koha/koha-deploy/ARCHITECTURE.md)

- Що синхронізовано з фактом:
  - видалений локальний `tunnel` сервіс зі стеку `koha-deploy`;
  - edge-модель доступу: `external Cloudflare Tunnel -> Traefik -> Koha`;
  - gateway-підключення Traefik до `koha-deploy_kohanet`;
  - домени як code через `KOHA_OPAC_SERVERNAME` / `KOHA_INTRANET_SERVERNAME`;
  - додані/описані модулі `domain-prefs` та `trusted-proxies`;
  - зафіксовано real-IP модель (`remoteip.conf`, `mod_remoteip`, `CF-Connecting-IP`).

- Перевірено:
  - документація відповідає актуальному `docker-compose.yaml` і `scripts/bootstrap-live-configs.sh`;
  - навігаційні посилання в README узгоджені зі структурою репозиторію.

### 9) Fix CD-deploy after tunnel removal: прибрано `tunnel` з GitHub Actions service lists

- Контекст:
  - після міграції на edge-модель `external Cloudflare Tunnel -> Traefik -> Koha` локальний сервіс `tunnel` видалено з `docker-compose.yaml`;
  - CD job у `.github/workflows/ci-cd-checks.yml` все ще посилався на `tunnel`, що спричиняло падіння deploy через SSH:
    - `no such service: tunnel`.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)

- Зміни:
  - `DEPLOY_PULL_SERVICES`: `db koha tunnel` -> `db koha`;
  - `DEPLOY_SERVICES`: `db es rabbitmq memcached koha tunnel` -> `db es rabbitmq memcached koha`.

- Перевірено:
  - конфіг workflow узгоджений з фактичним складом сервісів у `docker-compose.yaml`;
  - root-cause помилки `no such service: tunnel` усунуто на рівні CI/CD конфігурації.

### 10) IaC для `IntranetUserJS`: patch-модуль з env-driven змінними (без ручного UI)

- Контекст:
  - значення `IntranetUserJS` раніше вставлялось вручну через Koha UI;
  - для відповідності SSOT/IaC додано кероване оновлення через deploy-репозиторій.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-intranet-user-js.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-intranet-user-js.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - додано bootstrap-модуль `intranet-user-js`, який оновлює `systempreferences.IntranetUserJS` з файлу `IntranetUserJS.js`;
  - перед записом у БД модуль підставляє env-значення в JS-константи:
    - `KDV_API_URL`
    - `KDV_REPO_DOMAIN`
    - `KDV_POLLING_INTERVAL_MS`
  - додано env-ключі конфігурації:
    - `KOHA_INTRANET_USER_JS_FILE`
    - `KDV_API_URL`
    - `KDV_REPO_DOMAIN`
    - `KDV_POLLING_INTERVAL_MS`.

- Перевірено:
  - `bash ./scripts/verify-env.sh` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --module intranet-user-js --dry-run` — OK.

### 11) Fix: кнопка з `IntranetUserJS` не з'являлась у staff UI через пізнє створення toolbar

- Симптом:
  - після успішного patch/restart значення `IntranetUserJS` було в БД, але кнопка у `catalogue/detail.pl` не рендерилась.

- Root cause:
  - у поточному Koha toolbar на detail-сторінці створюється динамічно JS-ом;
  - кастомний `IntranetUserJS` шукав `#toolbar` лише один раз у `$(document).ready(...)` і завершувався, якщо елемент ще не існував.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/IntranetUserJS.js](/home/pinokew/Koha/koha-deploy/IntranetUserJS.js)

- Зміни:
  - додано `getToolbar()` з fallback на `.btn-toolbar`;
  - `checkAndRenderButton(...)` тепер має retry-механізм (до 20 спроб кожні 500ms), щоб дочекатися появи toolbar;
  - додано guard від дублювання кнопок при повторних викликах.

- Перевірено:
  - `bootstrap-live-configs --module intranet-user-js --no-restart` оновив `systempreferences.IntranetUserJS` (`value_len` збільшився після фікса);
  - `docker compose restart koha` виконано.

### 12) Rollback: прибрано IaC-патч для `IntranetUserJS`, повернення до ручного оновлення через UI

- Контекст:
  - за операційним рішенням відмовились від автоматичного patch-модуля для `systempreferences.IntranetUserJS`;
  - повернення до простішого процесу: вставка JS-коду вручну через Koha UI.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - видалено файл:
    - `/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-intranet-user-js.sh`

- Зміни:
  - модуль `intranet-user-js` прибрано з `bootstrap-live-configs` (help/module list/module mapping);
  - прибрано env-ключі `KOHA_INTRANET_USER_JS_FILE`, `KDV_API_URL`, `KDV_REPO_DOMAIN`, `KDV_POLLING_INTERVAL_MS`.

- Перевірено:
  - `bash ./scripts/verify-env.sh` — OK.

## 2026-03-14

### 13) Мережева ізоляція Koha sidecar-сервісів: Traefik від'єднано від `kohanet`, маршрутизація через `proxy-net`

- Контекст:
  - ціль: залишити публічний доступ до Koha через Traefik, але прибрати мережевий доступ Traefik до внутрішніх сервісів Koha-стеку (`db/es/rabbitmq/memcached`).

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)
  - [/home/pinokew/Koha/koha-deploy/ARCHITECTURE.md](/home/pinokew/Koha/koha-deploy/ARCHITECTURE.md)
  - [/home/pinokew/Traefik/docker-compose.yml](/home/pinokew/Traefik/docker-compose.yml)

- Зміни:
  - `koha` підключено до двох мереж: `koha-deploy_kohanet` + `proxy-net`;
  - на `koha` змінено label `traefik.docker.network` з `koha-deploy_kohanet` на `proxy-net`;
  - у `koha-deploy` оголошено зовнішню мережу `proxy-net` (`external: true`);
  - у Traefik stack прибрано мережу `koha-kohanet`/`koha-deploy_kohanet` з `traefik` сервісу;
  - архітектурну документацію синхронізовано під модель:
    - `Traefik <-> koha` через `proxy-net`;
    - `koha <-> sidecar services` через `koha-deploy_kohanet`.

- Перевірено (health/services/data):
  - `docker compose config -q` для `koha-deploy` — OK;
  - `docker compose config -q` для `/home/pinokew/Traefik` — OK;
  - `docker inspect traefik` -> мережі: тільки `proxy-net`;
  - `docker inspect koha-deploy-koha-1` -> мережі: `koha-deploy_kohanet`, `proxy-net`;
  - `koha` після recreate перейшов у `healthy`;
  - smoke через Traefik entrypoint (`Host: library.pinokew.buzz`, `Host: koha.pinokew.buzz`) -> `HTTP/1.1 200 OK`.

## 2026-03-16

### 14) Ітерація 2.3 (тільки Matomo tracking-код): автоматичний patch для OPAC JS через bootstrap modules

- Контекст:
  - реалізовано лише етап інтеграції tracking-коду (без CSP/Phase 2.4), за ітеративним підходом.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-opac-matomo.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-opac-matomo.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/docs/snippets/koha-opac-tracker.js](/home/pinokew/Koha/koha-deploy/docs/snippets/koha-opac-tracker.js)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - додано новий модуль `opac-matomo`, який оновлює Koha system preference для OPAC JS зі сніппета;
  - додано керований файл сніппета `docs/snippets/koha-opac-tracker.js` з placeholder-параметрами;
  - додано env-параметри:
    - `MATOMO_BASE_URL`
    - `MATOMO_SITE_ID`
    - `MATOMO_SNIPPET_FILE`
    - `KOHA_OPAC_JS_PREF_KEY`
  - під час валідації уточнено ключ налаштування Koha: використано `OPACUserJS` (а не `OpacCustomJS`).

- Перевірено (services/data):
  - `bash ./scripts/verify-env.sh` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --module opac-matomo --dry-run` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --module opac-matomo --no-restart` — OK;
  - у БД: `systempreferences.OPACUserJS` оновлено (`value_len=509`, preview містить Matomo snippet).

### 15) Ітерація 2.3 (розширення): DNT + SiteSearch + Device Dimension + configurable tracker URL

- Контекст:
  - виконано наступний крок в межах тієї ж фази 2.3 (без переходу до CSP/2.4).

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/docs/snippets/koha-opac-tracker.js](/home/pinokew/Koha/koha-deploy/docs/snippets/koha-opac-tracker.js)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-opac-matomo.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-opac-matomo.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - у OPAC tracker додано:
    - `setDoNotTrack(true)`;
    - site-search tracking helper `enableSiteSearch('q')` (через `trackSiteSearch` по query-param);
    - `setCustomDimension(1, DeviceType)` (`Mobile`/`Desktop`);
    - configurable `setTrackerUrl(...)` через `MATOMO_TRACKER_URL` (готово для masked endpoint);
  - модуль patch тепер підставляє нові параметри зі змінних оточення.

- Додано env-параметри:
  - `MATOMO_TRACKER_URL`
  - `MATOMO_SITE_SEARCH_QUERY_PARAM`
  - `MATOMO_DEVICE_DIMENSION_ID`

- Перевірено (services/data):
  - `bash ./scripts/verify-env.sh` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --module opac-matomo --no-restart` — OK;
  - у БД `systempreferences.OPACUserJS`:
    - `value_len=978`;
    - присутні маркери `setDoNotTrack`, `trackSiteSearch`, `setCustomDimension`, `setTrackerUrl`.

### 16) Ітерація 2.3 (masked endpoint): переключено `MATOMO_TRACKER_URL` + успішний OPAC network smoke-check

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - `MATOMO_TRACKER_URL` переключено на masked endpoint:
    - `https://matomo.pinokew.buzz/js/ping`

- Важливе спостереження:
  - після direct SQL update в `systempreferences` OPAC міг продовжувати віддавати старий `OPACUserJS` через кеш sysprefs;
  - для актуалізації виконано restart `memcached` + `koha`.

- Перевірено (OPAC DevTools Network):
  - у HTML присутні маркери `window._paq`, `setTrackerUrl`, masked endpoint;
  - у мережі зафіксовано запити:
    - `https://matomo.pinokew.buzz/matomo.js`
    - `https://matomo.pinokew.buzz/js/ping?...`

### 17) Ітерація 2.4 (перший крок): ввімкнено `Content-Security-Policy-Report-Only` для Koha

- Контекст:
  - перехід до наступного етапу після валідації Matomo tracking;
  - реалізовано тільки `Report-Only` режим (без enforcement).

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-apache-csp-report-only.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-apache-csp-report-only.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)
  - [/home/pinokew/Koha/koha-deploy/apache/csp-report-only.conf](/home/pinokew/Koha/koha-deploy/apache/csp-report-only.conf)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)

- Зміни:
  - додано bootstrap-модуль `csp-report-only`, який генерує керований Apache конфіг заголовка `Content-Security-Policy-Report-Only` з `.env`;
  - `koha` startup тепер idempotent вмикає модулі Apache `remoteip` + `headers`;
  - у `koha` додано mount `apache/csp-report-only.conf` -> `/etc/apache2/conf-enabled/zz-koha-csp-report-only.conf`;
  - додано env-керування директивами (`default-src`, `script-src`, `connect-src`, `img-src`, `style-src`, `base-uri`, `form-action`, `frame-ancestors`, `report-uri`).

- Перевірено (health/services/network):
  - `bash ./scripts/verify-env.sh` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --module csp-report-only` — OK;
  - `apache2ctl -M` у `koha` містить `headers_module`;
  - локально в контейнері (`127.0.0.1:8082`) присутній header `Content-Security-Policy-Report-Only`;
  - публічно (`https://library.pinokew.buzz/...`) присутній header `content-security-policy-report-only`;
  - OPAC DevTools Network після включення CSP: `matomo.js` та `js/ping` продовжують успішно завантажуватись.
