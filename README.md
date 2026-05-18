# 🏆 Koha Deploy – Production Library Stack

> **Вичерпна операційна документація для production-стеку Koha Library Management System.**  
> Оркестровано Docker Compose, керовано через env-SSOT, розгортається через безпечний CI/CD.

[![Статус](https://img.shields.io/badge/status-production-brightgreen)]()
[![Версія](https://img.shields.io/badge/version-2026_Q2-blue)]()
[![Ліцензія](https://img.shields.io/badge/license-AGPL-green)]()
[![Безпека](https://img.shields.io/badge/security-hardened-blueviolet)]()
[![Docker](https://img.shields.io/badge/runtime-Docker%20Compose-2496ED)]()

---

## 📋 Зміст

- [Поточний статус](#-поточний-статус)
- [Про проєкт](#-про-проєкт)
- [Архітектура стеку](#-архітектура-стеку)
- [Топологія репозиторію](#-топологія-репозиторію)
- [Топологія системи](#-топологія-системи)
- [Конфігураційна модель](#-конфігураційна-модель)
- [Безпека](#-безпека)
- [Локальні оточення](#-локальні-оточення)
- [Перший запуск](#-перший-запуск)
- [Операційні процедури](#-операційні-процедури)
- [Деплой на production](#-деплой-на-production)
- [CI/CD架構](#-cicd-архітектура)
- [Моніторинг та Алерти](#-моніторинг-та-алерти)
- [Troubleshooting](#-troubleshooting)
- [Посилання та навігація](#-посилання-та-навігація)

---

## 🚦 Поточний статус

> Оновлюється з кожною значною змін у виробництві та планах розвитку.

| Параметр | Значення |
|---|---|
| **Поточна версія** | `2026 Q2` (Swarm + SOPS + IaC completeness) |
| **Стадія** | **Production** |
| **Останній реліз** | 2026-05-10 |
| **Наступний мілстоун** | CSP enforcement (Roadmap 2.4) + Observability (Roadmap 2.1) |
| **Відомі критичні баги** | `0` → [Issues](docs/ROADMAP_PROD.md) |
| **Технічний борг** | 🟡 **Середній** — див. [docs/ROADMAP_PROD.md](docs/ROADMAP_PROD.md#-performance-baseline) |

### Активні ініціативи

- ✅ Базова безпека та хардeнінг (Roadmap 1.1–1.4): **CLOSED**
- ✅ Scripts refactoring / SOPS env-flow (Категорії 1а/1б/2): **CLOSED**
- ✅ Swarm deploy orchestrator + versioned Docker secrets: **CLOSED**
- ✅ IaC completeness (OIDC, Identity Provider, search-prefs, api-prefs, opac-matomo, CSP): **CLOSED**
- ✅ Backup offsite via rclone + textfile metrics + test-restore.sh: **CLOSED**
- 🔄 Спостережуваність (_Observability_): **IN PROGRESS**
  - Backup/restore freshness metrics через Node Exporter textfile collector
  - Планується: Prometheus/Alertmanager, розподілене трасування
- 🔄 CSP enforcement (Roadmap 2.4): **IN PROGRESS**
  - CSP у `report-only` режимі, enforcement заблокований `unsafe-eval` (Gettext)
  - Наступний крок: ідентифікувати enforced CSP runtime source, фіналізувати allowlist
- ⏸️ Performance baseline: **SCHEDULED**
  - Передбачається: MariaDB tuning, SLO-driven metrics

### Що саме було закрито

1. **Секрети та CI/CD**: обов'язкові перевірки на `main` (gitleaks, shellcheck, hadolint, Trivy config, `paths-ignore` для docs).
2. **Runtime hardening**: `security_opt`, `cap_drop`, memory/cpu limits для всіх сервісів.
3. **Identity lockdown**: OPAC password reset заблокована через `koha-lockdown-password-prefs.sh`.
4. **Supply-chain**: Trivy config gate в CI.
5. **Backup/Restore**: full-featured з dry-run, PITR, автоматичний ES rebuild, rclone offsite, test-restore smoke.
6. **CI/CD deploy**: автоматичний деплой на `main` через SSH; Swarm orchestrator з SOPS-розшифровкою.
7. **Traefik gateway**: edge access через `Cloudflare Tunnel -> Traefik -> proxy-net -> koha`; tunnel сервіс видалено з compose.
8. **SOPS env-flow**: `env.dev.enc`/`env.prod.enc` як SSOT; безпечний dotenv-parser без `source`/eval; автономні скрипти на `/dev/shm`.
9. **IaC completeness**: всі ключові sysprefs/config керовані через bootstrap модулі (OIDC, MS365 Identity Provider, Matomo, CSP, SearchEngine, RESTBasicAuth, domain, DB credentials).
10. **Elasticsearch index guard**: smart guard з auto-reindex при deploji на порожньому volume.

### Відомі обмеження

- Elasticsearch 8.x без x-pack (для production рекомендується x-pack authentication).
- CSP у `report-only` режимі (`CSP_MODE=report-only`); enforcement блокується `unsafe-eval` Koha Gettext/i18n.
- Розподілене трасування (Jaeger/Tempo) ще не інтегровано.
- `install-collect-logs-timer.sh` потребує синхронізації systemd unit з autonomous env contract перед production install.

---

## 🎯 Про проєкт

### Призначення

Це **deploy-репозиторій** для production-оточення **Koha Library Management System** — комплексної системи управління бібліотеками з підтримкою:
- каталогізації, розшифрування та видачі матеріалів;
- управління користувачами (патрони, персонал, гості);
- аналізу та звітності;
- інтеграціями з ILS, поштовими послугами, платіжними системами.

### Аудиторія

- **Бібліотечні установи** (державні, приватні, освітні);
- **Системні адміністратори** та DevOps команди;
- **Консультанти та інтегратори** Koha;
- **Розробники** розширень та localization.

### Ключові можливості системи

| Функцій | Опис |
|---|---|
| **OPAC (Public Interface)** | Каталог пошуку, мій аккаунт, резервування, історія видачі |
| **Intranet (Staff Interface)** | Бібліографія, управління користувачами, видача, повернення, звіти |
| **Elasticsearch** | Швидкий повнотекстовий пошук і фасетна навігація |
| **Message Queue (RabbitMQ)** | Асинхронна обробка (відправка листів, індексація, фонові завдання) |
| **Caching (Memcached)** | Прискорення сеансів та часто запитуваних даних |
| **Secure Access (Traefik Gateway)** | Зовнішній доступ через Traefik + external Cloudflare Tunnel |
| **Detailed Logging** | JSON-структуровані логи з ротацією дискових обсягів |

### Що НЕ входить у скоп цього репо

- **Application development** — код Koha лежить у [koha-community/koha](https://github.com/koha-community/koha).
- **Database schema design** — управляється Koha інстанціацією.
- **Help desk / User support** — відділ користувача.
- **Plugin development** — розроблюється окремо, інтегрується через `koha-conf.xml`.

---

## ⚙️ Архітектура стеку

### Зведена таблиця технологій

| Шар | Технологія | Версія | Назначення |
|---|---|---|---|
| **Web Framework** | Koha | 25.x | Система управління бібліотекою |
| **Web Server** | Plack/Apache2 | modern | HTTP-сервер, Load balancing |
| **База даних** | MariaDB | 11.x | Основне сховище даних |
| **Search Engine** | Elasticsearch | 8.19.6 | Індексація та пошук |
| **Кеш** | Memcached | 1.6.x | Session storage, cache layer |
| **Черга подій** | RabbitMQ | 3.x | Message broker для async-операцій |
| **Контейнеризація** | Docker + Compose | latest | Оркестрація сервісів |
| **Edge Gateway** | Traefik | 3.6.x | Host-based routing для OPAC/Staff |
| **External Ingress** | Cloudflare Tunnel | managed outside repo | Без прямого expose Koha портів |
| **CI/CD** | GitHub Actions | latest | Пайплайни дослідження та деплою |
| **Логування** | JSON-file driver | native | Docker native logging з ротацією |

### Принципи архітектури

| Принцип | Опис |
|---|---|
| **Single Container Network** | Усе в одній `docker-мережі` (`kohanet`) без публічних портів|
| **SSOT Configuration** | Вся runtime-конфігурація в `.env` + `docker-compose.yaml` |
| **Immutable Deployments** | Контейнери непорушні; конфіг через env/volumes |
| **Least Privilege** | `cap_drop`, `security_opt`, resource limits для всіх сервісів |
| **Health Checks** | Усi критичні сервіси мають встроєні healthchecks |
| **Log Rotation** | JSON-file driver з `max-size` / `max-file` для уникнення overflow |
| **Fail-Fast** | Startup-процес перевіряє критичні умови; блокує неправильні конф |

### Схема взаємодії компонентів

```
    ┌─────────────────────────────────────────────────────────┐
   │   EXTERNAL USERS (OPAC) & STAFF (Intranet)            │
   │     (через зовнішній Cloudflare Tunnel stack)         │
    └────────────────────┬────────────────────────────────────┘
                         │ HTTPS
    ┌────────────────────▼────────────────────────────────────┐
   │   Cloudflare Tunnel (external stack) -> Traefik (:80)  │
   │   Host: library.pinokew.buzz / koha.pinokew.buzz      │
   │   Network: proxy-net (external, shared з Traefik)     │
    └────────────────────┬────────────────────────────────────┘
                         │ proxy-net (Traefik -> koha only)
    ┌────────────────────▼────────────────────────────────────┐
    │  KOHA (Plack/Apache)                                   │
    │  - Networks: proxy-net (Traefik) + kohanet (sidecars) │
    │  - Apache: remoteip + headers modules                 │
    │  - Health check: http://koha:8081 (intranet)          │
    └────────┬───────────┬────────────┬──────────────────────┘
             │           │            │  (kohanet only — Traefik не бачить)
      ┌──────▼──┐  ┌────▼────┐  ┌───▼────┐
      │  MariaDB │  │RabbitMQ │  │  ES    │
      │  (db)    │  │ (queue) │  │ (8.x)  │
      └──────────┘  └────┬────┘  └────────┘
                         │
                    ┌────▼──────┐
                    │ Memcached  │
                    │ (cache)    │
                    └────────────┘

    kohanet = koha-deploy_kohanet (internal, sidecars isolated)
    proxy-net = external shared network (Traefik <-> koha only)
   No host-published ports for Koha services
    Resource-limited: CPU/memory/pids/ulimits
```

---

## 🗂️ Топологія репозиторію

```
koha-deploy/
│
├── 📄 docker-compose.yml               # Основна оркестрація сервісів (Compose)
├── 📄 docker-compose.swarm.yml         # Swarm-overlay (secrets, configs, image overrides)
├── 📄 env.dev.enc                      # SOPS-зашифрований env для dev
├── 📄 env.prod.enc                     # SOPS-зашифрований env для prod
├── 📄 IntranetUserJS.js                # Kастомний JS для Intranet (вставляється вручну через UI)
├── 📄 .gitignore                       # git-фільтри
│
├── 📁 scripts/                         # Операційні скрипти (bash)
│   ├── verify-env.sh                   # Валідація .env перед запуском
│   ├── init-volumes.sh                 # Ініціалізація host volumes + ACL
│   ├── bootstrap-live-configs.sh       # Оркестратор live-патчів Koha (--env-file, --module)
│   ├── deploy-orchestrator-swarm.sh    # Swarm deploy: init → secret render → deploy → bootstrap
│   ├── render-versioned-env-secret.sh  # Versioned Docker secrets (env payload, DB, RabbitMQ)
│   ├── koha-elasticsearch-index-guard.sh # Smart ES index guard при deploy
│   ├── koha-lockdown-password-prefs.sh # Блокування password sysprefs
│   ├── backup.sh                       # Full backup DB + volumes (--env prod|dev, rclone offsite)
│   ├── restore.sh                      # Restore / PITR procedure (--env prod|dev)
│   ├── test-restore.sh                 # Restore smoke-test у тимчасовий MariaDB container
│   ├── collect-docker-logs.sh          # Збір логів (--env prod|dev, Swarm mode)
│   ├── install-collect-logs-timer.sh   # Встановлення systemd timer
│   ├── check-ports-policy.sh           # Перевірка publish-портів
│   ├── check-internal-ports-policy.sh  # Перевірка внутрішньої мережевої політики
│   │
│   ├── 📁 lib/                         # Спільні runtime helpers
│   │   ├── autonomous-env.sh           # SOPS decrypt для cron/manual (Category 2)
│   │   ├── orchestrator-env.sh         # Env resolver для deploy-adjacent scripts (Category 1б)
│   │   └── docker-runtime.sh           # docker_runtime_exec: compose|swarm adapter
│   │
│   └── 📁 patch/                       # Модулі live-конфігу
│       ├── _patch_common.sh            # Спільні утиліти
│       ├── patch-koha-conf-xml.sh      # Базова конфігурація
│       ├── patch-koha-conf-xml-db.sh   # DB credentials (перед іншими модулями)
│       ├── patch-koha-conf-xml-trusted-proxies.sh # trusted proxies chain
│       ├── patch-koha-conf-xml-memcached.sh  # Memcached інтеграція
│       ├── patch-koha-conf-xml-message-broker.sh # RabbitMQ інтеграція
│       ├── patch-koha-conf-xml-smtp.sh # SMTP конфіг
│       ├── patch-koha-conf-xml-timezone.sh    # Timezone setup
│       ├── patch-koha-conf-xml-verify.sh      # Верифікація XML + DB/RabbitMQ credentials
│       ├── patch-koha-sysprefs-search.sh      # SearchEngine syspref (Elasticsearch|Zebra)
│       ├── patch-koha-sysprefs-api.sh         # RESTBasicAuth syspref
│       ├── patch-koha-sysprefs-domain.sh      # OPAC/Staff URL sysprefs
│       ├── patch-koha-sysprefs-oidc.sh        # OIDC sysprefs (--discover/--apply/--verify)
│       ├── patch-koha-identity-provider.sh    # MS365/OIDC identity_providers table
│       ├── patch-koha-sysprefs-opac-matomo.sh # Matomo tracking snippet → OPACUserJS
│       ├── patch-koha-apache-csp-report-only.sh # CSP-Report-Only Apache header
│       └── patch-koha-templates.sh     # deprecated wrapper → bootstrap-live-configs
│
├── 📁 systemd/                         # Systemd service/timer
│   ├── koha-deploy-collect-logs.service
│   └── koha-deploy-collect-logs.timer
│
├── 📁 elasticsearch/                   # Local ES Dockerfile (з analysis-icu)
│   └── Dockerfile
├── 📁 rabbitmq/                        # Local RabbitMQ Dockerfile
│   ├── Dockerfile
│   └── enabled_plugins
├── 📁 memcached/                       # Local Memcached Dockerfile
│   └── Dockerfile
├── 📁 apache/                          # Managed Apache overlays
│   ├── remoteip.conf                   # Real client IP via CF-Connecting-IP
│   └── csp-report-only.conf            # Content-Security-Policy-Report-Only header
│
├── 📁 docs/                            # Документація
│   ├── ARCHITECTURE.md                 # Архітектурні правила & обмеження
│   ├── ROADMAP_PROD.md                 # Development roadmap & priorities
│   ├── RUNBOOK_DR.md                   # Disaster Recovery procedures
│   ├── scripts_runbook.md              # Scripts contracts & usage reference
│   ├── scrypts_refactoring.md          # Refactoring notes
│   ├── changelogs/                     # Versioned changelog volumes
│   │   ├── CHANGELOG_2026_VOL_01.md
│   │   ├── CHANGELOG_2026_VOL_02.md
│   │   ├── CHANGELOG_2026_VOL_03.md
│   │   ├── CHANGELOG_2026_VOL_04.md
│   │   ├── CHANGELOG_2026_VOL_05.md
│   │   ├── CHANGELOG_2026_VOL_06.md
│   │   └── CHANGELOG_2026_VOL_07.md (active)
│   └── snippets/                       # Managed code snippets
│       └── koha-opac-tracker.js        # Matomo OPAC tracking snippet
│
├── 📁 archive/                         # Архів (не редагувати)
│   └── AGENTS.md                       # New session start guide
│
├── 📁 .github/workflows/               # CI/CD
│   └── ci-cd-checks.yml                # Lint, test, deploy workflow
│
├── 📄 CHANGELOG.md                     # Changelog index
└── 📄 README.md                        # **ВИ ТУТ** (це файл)
```

---

## 🏗️ Топологія системи (docker-compose)

### Сервіси та їхні ролі

| Сервіс | Образ | Назначення | Порти (внутрішні) | Health Check |
|---|---|---|---|---|
| **koha** | ext. registry | Web-додаток Koha (Plack) | 8082 (OPAC), 8081 (Intranet) | HTTP 8081, 15s interval |
| **db** | `mariadb:11` | Реляційна БД | 3306 | mariadb-admin ping, 10s |
| **es** | local build | Elasticsearch search | 9200 | curl http://9200, 10s |
| **rabbitmq** | local build | Message queue, async | 5672 (AMQP), 61613 (STOMP), 15672 (mgmt) | rabbitmq-diagnostics ping |
| **memcached** | local build | Розподілений кеш | 11211 | TCP socket (auto) |

### Залежності запуску

```
koha
  depends_on:
    - db (service_healthy)
    - rabbitmq (service_healthy)
    - memcached (service_started)
    - es (service_healthy)
```

### Resource Limits

| Сервіс | Memory | CPU | PID Limit |
|---|---|---|---|
| **koha** | 2 GB (default) | 1.50 | 1024 |
| **db** | 2 GB (default) | 1.50 | 1024 |
| **es** | 1 GB (default) | 1.00 | 1024 |
| **rabbitmq** | 512 MB (default) | 1.00 | 1024 |
| **memcached** | 256 MB (default) | 0.50 | 1024 |

> **Примітка**: Усі ліміти можуть бути перевизначені через `.env` змінні (e.g., `KOHA_MEM_LIMIT`, `DB_CPUS`).

---

## 🔧 Конфігураційна модель

### SSOT (Single Source of Truth)

Вся runtime-конфігурація керується через SOPS-зашифровані env-файли:

1. **`env.dev.enc`** — SOPS-зашифрований env для dev оточення
2. **`env.prod.enc`** — SOPS-зашифрований env для production
3. **`docker-compose.yml`** — Compose-сервіси з env-підстановками
4. **`docker-compose.swarm.yml`** — Swarm overlay (secrets, configs, image overrides)

> **Розшифрування** відбувається автоматично через `sops --decrypt` у deploy pipeline або `scripts/lib/autonomous-env.sh` для cron/manual сценаріїв. Decrypted env **ніколи не записується в git**.

### Ключові категорії змінних

| Категорія | Приклади | Де зберігається |
|---|---|---|
| **Koha Config** | `KOHA_INSTANCE`, `KOHA_DOMAIN`, `KOHA_TIMEZONE` | env.*.enc |
| **Database** | `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_ROOT_PASS` | env.*.enc (secret) |
| **Elasticsearch** | `ELASTICSEARCH_HOST`, `USE_ELASTICSEARCH`, `KOHA_SEARCH_ENGINE` | env.*.enc |
| **RabbitMQ** | `RABBITMQ_USER`, `RABBITMQ_PASS`, `MB_HOST`, `MB_PORT` | env.*.enc (secret) |
| **Memcached** | `MEMCACHED_SERVERS` | env.*.enc |
| **Edge Domains** | `KOHA_OPAC_SERVERNAME`, `KOHA_INTRANET_SERVERNAME` | env.*.enc |
| **Trusted Proxies** | `KOHA_TRUSTED_PROXIES` | env.*.enc |
| **SMTP** | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_SSL_MODE` | env.*.enc (secret) |
| **OIDC Sysprefs** | `KOHA_OIDC_PREF__*`, `KOHA_OIDC_INCLUDE_EMPTY` | env.*.enc (secret) |
| **Identity Provider** | `KOHA_IDP_KEY`, `KOHA_IDP_SECRET`, `KOHA_IDP_WELL_KNOWN_URL` | env.*.enc (secret) |
| **Matomo Analytics** | `MATOMO_BASE_URL`, `MATOMO_SITE_ID`, `MATOMO_TRACKER_URL` | env.*.enc |
| **CSP** | `CSP_MODE`, `CSP_REPORT_ONLY_DEFAULT_SRC`, `CSP_REPORT_ONLY_SCRIPT_SRC` | env.*.enc |
| **Backup** | `BACKUP_PATH`, `BACKUP_RCLONE_REMOTE`, `BACKUP_RCLONE_FOLDER`, `BACKUP_RCLONE_RETENTION_DAYS` | env.*.enc |
| **Monitoring** | `NODE_EXPORTER_TEXTFILE_DIR`, `BACKUP_METRICS_FILE` | env.*.enc |
| **API** | `KOHA_REST_BASIC_AUTH` | env.*.enc |
| **Volume Paths** | `VOL_DB_PATH`, `VOL_KOHA_CONF`, `VOL_KOHA_DATA` | env.*.enc |
| **Resource Limits** | `KOHA_MEM_LIMIT`, `DB_CPUS`, `ES_MEM_LIMIT` | env.*.enc |
| **Logging** | `LOG_MAX_SIZE`, `LOG_MAX_FILE` | env.*.enc |
| **Swarm** | `STACK_NAME`, `ORCHESTRATOR_ES_GUARD`, `ORCHESTRATOR_SWARM_BUILD_SERVICES` | env.*.enc |

### Live-конфіг патчі

Сервіс Koha має `koha-conf.xml`, який може змінюватися runtime. Для цього використовується модульна система патчів:

```bash
# Усі модулі
bash scripts/bootstrap-live-configs.sh --env-file <env_file> --all

# Вибіркові модулі
bash scripts/bootstrap-live-configs.sh --env-file <env_file> --modules smtp,memcached

# Список підтримуваних модулів
bash scripts/bootstrap-live-configs.sh --list-modules

# Dry-run (без застосування)
bash scripts/bootstrap-live-configs.sh --env-file <env_file> --module db --dry-run
```

**Модулі (в `scripts/patch/`), порядок виконання:**
- `db` — DB credentials у `koha-conf.xml` (виконується **першим**)
- `patch-koha-conf-xml.sh` — базова Koha конфігурація
- `search-prefs` — `systempreferences.SearchEngine` (Elasticsearch|Zebra) + cache flush
- `api-prefs` — `systempreferences.RESTBasicAuth` + cache flush
- `domain-prefs` — OPAC/Staff URL sysprefs (`OPACBaseURL`, `staffClientBaseURL`)
- `oidc-prefs` — OIDC sysprefs (--discover/--apply/--verify з `KOHA_OIDC_PREF__*`)
- `identity-provider` — MS365/OIDC `identity_providers` + `identity_provider_domains`
- `memcached` — Memcached інтеграція
- `message-broker` — RabbitMQ інтеграція
- `smtp` — SMTP параметри
- `timezone` — Часовий пояс
- `trusted-proxies` — trusted proxies chain у `koha-conf.xml`
- `opac-matomo` — Matomo tracking snippet → `systempreferences.OPACUserJS`
- `csp-report-only` — генерація `apache/csp-report-only.conf` з env
- `patch-koha-conf-xml-verify.sh` — верифікація XML + DB/RabbitMQ credentials

---

## 🔒 Безпека

### Security-First Принципи

| Принцип | Реалізація |
|---|---|
| **Secrets не комітяться** | `env.*.enc` SOPS-зашифровані; CI checks gitleaks; безпечний dotenv-parser без `source`/eval |
| **Least Privilege** | `cap_drop: ALL`, `security_opt: no-new-privileges`, мінімальні UNIX-права |
| **Network Isolation** | `koha` на двох мережах: `kohanet` (сайдкари) + `proxy-net` (Traefik); sidecars відізольовані від Traefik |
| **Edge via Gateway** | External Cloudflare Tunnel -> Traefik (proxy-net) -> koha |
| **Container Hardening** | `pids_limit`, `ulimits`, memory/cpu limits, seccomp-profiles (можна додати) |
| **Logging Security** | Логи вивантажуються наприкінці; не залишаються в контейнері |
| **Image Scanning** | Триви config gate в CI; рекомендовано image scan |
| **Identity Lockdown** | OPAC password reset вимкнено (`OpacResetPassword=0`) |

### Secrets Management

**Недопустимо (❌):**
- Комітити `env.dev.enc` / `env.prod.enc` без SOPS-шифрування
- Зберігати паролі в `docker-compose.yml` або git
- Використовувати `source`/eval для env-файлів (inject injection risk)

**Допустимо (✅):**
- `env.*.enc` комітити (SOPS-зашифровані, безпечно)
- Розшифровувати через SOPS Age у `/dev/shm` з `trap` cleanup
- Передавати secrets через CI/CD secrets (GitHub Secrets) + versioned Docker secrets
- Ротація паролів за розписанням

### Переповідні точки безпеки

1. **Database credentials** — передавати через `.env`, ніколи у кодах
2. **Cloudflare token** — GitHub Secret + ansible vault для production
3. **SMTP credentials** — `.env`, ротація за розписанням
4. **RabbitMQ credentials** — генерувати на першому запуску, зберігати безпечно

---

## 🖥️ Локальні оточення

> Передбачається розробка / testing на локальній машині (Linux/Mac).

### Передумови

```bash
# Перевірити наявність
docker version          # Docker 20.10+
docker compose version  # Docker Compose 2.0+
git --version           # Git 2.30+
bash --version          # Bash 4.0+
```

### Підготовка

1. **Клонувати репозиторій:**
   ```bash
   git clone https://github.com/yourorg/koha-deploy.git
   cd koha-deploy
   ```

2. **Розшифрувати та скопіювати env:**
   ```bash
   sops --decrypt env.dev.enc > .env   # для локального dev
   ```

3. **Редагувати `.env`** під ваше оточення (якщо потрібно):
   ```bash
   nano .env
   ```

   **Критичні змінні для локального запуску:**
   ```bash
   KOHA_INSTANCE=mylibrary          # Назва інстансу
   KOHA_DOMAIN=localhost            # Domain (local)
   KOHA_TIMEZONE=Europe/Kyiv        # Ваш часовий пояс
   
   DB_USER=koha                     # DB user
   DB_PASS=koha_password            # DB password (не secret для local)
   DB_ROOT_PASS=root_password       
   
   RABBITMQ_USER=koha               # RabbitMQ user
   RABBITMQ_PASS=rabbitmq_password  
   
   # Домени для Traefik host-based routing
   KOHA_OPAC_SERVERNAME=library.pinokew.buzz
   KOHA_INTRANET_SERVERNAME=koha.pinokew.buzz
   
   # Volume paths (localhot)
   VOL_DB_PATH=/var/lib/koha-deploy/mysql
   VOL_KOHA_CONF=/var/lib/koha-deploy/koha-conf
   VOL_KOHA_DATA=/var/lib/koha-deploy/koha-data
   VOL_KOHA_LOGS=/var/lib/koha-deploy/koha-logs
   VOL_ES_PATH=/var/lib/koha-deploy/elasticsearch
   ```

4. **Верифікувати конфігурацію:**
   ```bash
   bash scripts/verify-env.sh
   ```

---

## 🚀 Перший запуск

### Step 1: Стартувати сервіси

```bash
docker compose up -d --build
```

**Що відбувається:**
- MariaDB ініціалізується (перший запуск: ~30s)
- Elasticsearch стартує (перший запуск: ~2-3m)
- RabbitMQ та Memcached готуються
- Koha чекає, поки БД буде ready

### Step 2: Перевірити статус

```bash
docker compose ps
docker compose logs -f koha          # Follow Koha logs (Ctrl+C for exit)
```

**Очікуваний статус:**
```
NAME           IMAGE                    STATUS              PORTS
koha-db-1      mariadb:11              Up (healthy)
koha-es-1      koha-local-es:8.19.6    Up (healthy)
koha-rabbitmq-1 koha-local-rabbitmq    Up (healthy)
koha-memcache-1 koha-local-memcached   Up
koha-koha-1    <external-image>        Up (healthy)
```

### Step 3: Застосувати live-конфіги

```bash
bash scripts/bootstrap-live-configs.sh --all
```

**Що робить:**
- Patching `koha-conf.xml` для Memcached, RabbitMQ, SMTP, etc.
- Обновляє HTML-шаблони (якщо потрібні кастомізації)
- Перезавантажує Koha сервіс

### Step 4: Отримати доступ до OPAC / Intranet

**Локально через Traefik gateway (Host header):**
```bash
curl -I -H 'Host: library.pinokew.buzz' http://127.0.0.1:8080/
curl -I -H 'Host: koha.pinokew.buzz' http://127.0.0.1:8080/
```

**Credentials:**
- Default создается на першому запуску Koha
- Перевірити логи: `docker compose logs koha | grep -i "admin\|superuser"`

---

## 🛠️ Операційні процедури

### SMTP Перевірка та Налаштування

1. **Заповнити SMTP змінні в `.env`:**
   ```bash
   SMTP_HOST=mail.example.com
   SMTP_PORT=587
   SMTP_USER=noreply@example.com
   SMTP_PASS=your_smtp_password
   SMTP_SSL_MODE=STARTTLS    # або TLS / PLAIN
   SMTP_FROM_ADDRESS=library@example.com
   SMTP_FROM_NAME="My Library"
   ```

2. **Застосувати SMTP-патч:**
   ```bash
   bash scripts/bootstrap-live-configs.sh --modules smtp
   ```

3. **Протестувати відправку:**
   ```bash
   bash scripts/test-smtp.sh
   ```

   **Очікуваний результат:**
   ```
   [INFO] Testing SMTP via koha@localhost...
   [SUCCESS] Email sent to test@example.com
   ```

### Backup

**Full backup (DB + volumes):**
```bash
bash scripts/backup.sh --env prod         # production
bash scripts/backup.sh --env dev --dry-run # dry-run (no write)
```

**Offsite копіювання (rclone):**
- `BACKUP_RCLONE_REMOTE` + `BACKUP_RCLONE_FOLDER` в env вмикають offsite upload
- `BACKUP_RCLONE_RETENTION_DAYS` керує retention на remote (дефолт `0` = вимкнено)
- Локальний `BACKUP_RETENTION_DAYS` й `BACKUP_RCLONE_RETENTION_DAYS` незалежні

**Monitoring metrics:**
- `backup.sh` пише `koha_backup.prom` у `${NODE_EXPORTER_TEXTFILE_DIR}`

**Restore smoke-test:**
```bash
bash scripts/test-restore.sh --env prod   # імпорт SQL dump у temp MariaDB, не торкає prod
```

### Restore

**Dry-run (без змін):**
```bash
bash scripts/restore.sh --env prod --dry-run
```

**Full restore (PITR):**
```bash
bash scripts/restore.sh --env prod
```

**Потім:**
```bash
bash scripts/bootstrap-live-configs.sh --env-file <env_file> --all
```

### Логування та Діагностика

**Збір логів з усіх сервісів:**
```bash
bash scripts/collect-docker-logs.sh
```

**Автоматичний планований збір (через systemd timer):**
```bash
bash scripts/install-collect-logs-timer.sh

# Перевірити installation
systemctl status koha-deploy-collect-logs.timer
systemctl list-timers koha-deploy-collect-logs.timer
```

**Моніторити live-логи:**
```bash
docker compose logs -f --tail=50        # Усі сервіси (50 останніх рядків)
docker compose logs -f koha             # Тільки Koha
docker compose logs -f db               # Тільки MariaDB
```

---

## 📡 Деплой на production

> Детальніше див. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) і [docs/RUNBOOK_DR.md](docs/RUNBOOK_DR.md).

### Manual Deploy (Compose, на сервері)

**Передумови:**
- SSH доступ до сервера
- Git доступ до `main` branch
- `env.prod.enc` у корені репо, `sops` + Age key налаштовані

**Процедура:**

```bash
# SSH на сервер
ssh user@production.server
cd /opt/Koha/koha-deploy

# Оновити код
git fetch origin
git reset --hard origin/main

# Оновити сервіси
docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml build --no-cache
docker compose -f docker-compose.yml up -d --remove-orphans

# Застосувати конфіги
bash scripts/bootstrap-live-configs.sh --env-file <(sops -d env.prod.enc) --all

# Перевірити health
bash scripts/verify-env.sh
docker compose -f docker-compose.yml ps
```

### Swarm Deploy (Production Orchestrator)

**Передумови:**
- Docker Swarm проініціалізовано (`docker swarm init`)
- `env.prod.enc` + SOPS Age key
- Versioned Docker secrets створюються автоматично

**Ідеологія Swarm deploy:**
```
SECRET RENDER  ->  INIT VOLUMES  ->  STACK DEPLOY  ->  RECONCILE
    |                  |                  |                |
 versioned         host dirs           docker stack     smart update
 Docker secrets    ACL setup           deploy           (force only
 (env payload,     BACKUP_PATH                          if needed)
 DB, MQ)           KOHA_CONF
```

**Запуск:**
```bash
SERVER_ENV=prod bash scripts/deploy-orchestrator-swarm.sh
# або
bash scripts/deploy-orchestrator-swarm.sh --env prod

# Dry-run (без передачі на Docker)
ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh
```

**Post-deploy (виконується автоматично оркестратором):**
1. `bootstrap-live-configs.sh --all` (в Swarm runtime mode)
2. `koha-elasticsearch-index-guard.sh` (smart reindex при порожньому volume)
3. `koha-lockdown-password-prefs.sh` (OPAC password reset заблоковано)

### Automated Deploy (GitHub Actions)

Workflow: `.github/workflows/ci-cd-checks.yml`

**Trigger:** `push` на `main` branch

**Перевірки (CI):**
- Hadolint (Dockerfile linter)
- Shellcheck (bash linter)
- Docker Compose config validation
- Secret hygiene check (gitleaks)
- Trivy config scan (HIGH/CRITICAL, без image scan)
- Internal ports policy check
- `paths-ignore` фільтр: `**.md`, `.gitignore`, `archive/**` — пропускають CI при doc-only змінах

**Deploy (CD):**
- SSH connection до сервера (з GitHub Secrets)
- git fetch/reset/pull
- docker compose pull/build/up
- bootstrap-live-configs
- health-check verification

**Required GitHub Secrets:**
- `SERVER_HOST` — IP/hostname сервера
- `SERVER_USER` — SSH user
- `SERVER_SSH_KEY` — приватний SSH-ключ
- (optional) `TAILSCALE_AUTHKEY` — для безпеки через Tailscale

---

## 🔍 CI/CD Архітектура

### Workflow Stages

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Push to main                                    │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────▼──────────────┐
         │   ci-checks job          │  (fast-core)
         │   - Hadolint             │ /ci-cd-checks.yml
         │   - Shellcheck           │
         │   - Compose config       │
         │   - Secrets scan         │
         │   - Ports policy         │
         │   - Gitleaks             │
         └───────────┬──────────────┘
                     │
              ┌──────▼──────┐
              │  All passed?│
              └──────┬──────┘
                  Yes │
         ┌───────────▼──────────────┐
         │   cd-deploy job          │
         │   - SSH to server        │
         │   - git checkout main    │
         │   - docker pull/build    │
         │   - compose up -d        │
         │   - bootstrap-configs    │
         │   - health-check         │
         └──────────────────────────┘
```

### Security Gates

1. **Branch Protection** — усі commits на `main` потребують review
2. **Automation Checks** — усі CI-перевірки мають пройти
3. **Artifact Pinning** — усі external images повинні мати fixed digest (не `latest`)
4. **Secret Scanning** — gitleaks блокує commit з секретами

---

## 📊 Моніторинг та Алерти

### Вбудовані Health Checks

| Сервіс | Перевірка | Інтервал | Timeout | Retries | Start Period |
|---|---|---|---|---|---|
| koha | HTTP GET 8081 | 15s | 5s | 5 | 20s |
| db | mariadb-admin ping | 10s | 5s | 10 | 90s |
| es | curl http://9200 | 10s | 5s | 10 | 120s |
| rabbitmq | rabbitmq-diagnostics ping | 10s | 5s | 10 | 0s |
| memcached | TCP socket | (auto) | — | — | 0s |

**Перевірити статус:**
```bash
docker compose ps                   # Бачити .Status та (healthy/unhealthy)
docker compose exec koha sleep 1    # Trigger health-check
```

### Рекомендовані метрики для моніторингу

> Див. [ROADMAP_PROD.md → 2.1 Observability](ROADMAP_PROD.md#21-observability-логи-метрики-трасування-та-алерти)

| Метрика | Тип | Поріг / SLO |
|---|---|---|
| **HTTP 5xx errors** | Error Rate | < 1% (p95) |
| **DB Connection Pool** | Saturation | < 80% of max_connections |
| **Disk Usage** | Saturation | < 85% per volume |
| **Memory Usage** | Saturation | < 90% per service |
| **ES Heap Usage** | Saturation | < 75% |
| **Queue Depth (RabbitMQ)** | Queue | < avg 100 messages |
| **Response Time (p95)** | Latency | < 800ms for OPAC search |

### Логування

**Централізована збір логів:**
```bash
# JSON-file logs в Docker
docker inspect koha | jq '.[0].LogPath'

# Ручний експорт
docker compose logs --timestamps --no-color > logs_dump.txt

# Планований (systemd timer)
bash scripts/install-collect-logs-timer.sh
```

---

## 🧹 Troubleshooting

### Коха не стартує

```bash
# Перевірити логи
docker compose logs -f koha

# Чекати на DB readiness
docker compose logs db | grep -i healthy

# Перезапустити
docker compose restart koha
```

### DB connection errors

```bash
# Перевірити DB здоров'я
docker compose exec db mariadb-admin ping -h 127.0.0.1 -uroot -p$DB_ROOT_PASS

# Перевірити розміри
docker compose exec db du -h /var/lib/mysql

# Check slow queries
docker compose exec db tail -f /var/log/mysql/slow.log
```

### Elasticsearch issues

```bash
# Перевірити ES status
docker compose exec es curl http://localhost:9200/_cluster/health

# Rebuild ES index
docker compose exec koha koha-elasticsearch-indexer --rebuild

# Check disk space (ES needs space)
docker system df
```

### External Tunnel / Traefik routing issues

```bash
# Перевірити, що Koha healthy
docker compose ps koha

# Перевірити Traefik host routing локально
curl -I -H 'Host: library.pinokew.buzz' http://127.0.0.1:8080/
curl -I -H 'Host: koha.pinokew.buzz' http://127.0.0.1:8080/

# Перевірити real client IP в Apache access log
docker compose exec koha tail -n 20 /var/log/koha/apache/other_vhosts_access.log
```

### Недостатньо місця на диску

```bash
# Перевірити том usage
df -h $(echo $VOL_DB_PATH $VOL_KOHA_DATA $VOL_ES_PATH | tr ' ' '\n' | xargs dirname | sort -u)

# Прості способи вкоротити місце
docker system prune
docker volume prune

# Перевірити ротацію логів
ls -lh $(docker inspect koha | jq -r '.[0].LogPath' | xargs dirname)
```

---

## 📚 Посилання та навігація

### Для нової сесії (обов'язково прочитати)

1. **[archive/AGENTS.md](archive/AGENTS.md)** — guide для нової сесії
2. **[docs/ROADMAP_PROD.md](docs/ROADMAP_PROD.md)** — текущі пріоритети і що буде далі
3. **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — правила & обмеження проєкту

### Для операцій та коли щось ламається

- **[docs/RUNBOOK_DR.md](docs/RUNBOOK_DR.md)** — Disaster Recovery процедури
- **[docs/scripts_runbook.md](docs/scripts_runbook.md)** — Scripts contracts & usage reference
- **[CHANGELOG.md](CHANGELOG.md)** — індекс змін (у томах у `docs/changelogs/`)

### Для розробленння та fork'ів

- **archive/README.example.md** — template для нових проектів (не редагувати)
- **.github/workflows/ci-cd-checks.yml** — CI/CD логіка

### Зовнішні ресурси

| Проєкт | Посилання |
|---|---|
| **Koha Community** | https://koha-community.org |
| **Koha Manual** | https://koha-community.org/manual/latest |
| **Docker Docs** | https://docs.docker.com |
| **Docker Compose** | https://docs.docker.com/compose |
| **Elasticsearch** | https://www.elastic.co/guide/en/elasticsearch/reference/current |
| **MariaDB Docs** | https://mariadb.com/docs/reference |
| **RabbitMQ** | https://www.rabbitmq.com/documentation.html |

---

## 📝 Информация про автора та підтримку

> Ці документи та scripts підтримуються окремо. Для issues, questions, або PR див. GitHub repository.

**Контакти:**
- Репозиторій: [GitHub](https://github.com/yourorg/koha-deploy)
- Issues: [GitHub Issues](https://github.com/yourorg/koha-deploy/issues)
- Документація: [Wiki/Docs](https://github.com/yourorg/koha-deploy/wiki)

---

## 📋 Поточний Changelog

> Див. [CHANGELOG.md](CHANGELOG.md) для індексу томів. Активний том: [docs/changelogs/CHANGELOG_2026_VOL_07.md](docs/changelogs/CHANGELOG_2026_VOL_07.md)

**Останні оновлення (VOL_05–VOL_07):**
- ✅ Scripts refactoring: безпечний SOPS env-flow для Категорій 1а/1б/2 (без `source`/eval)
- ✅ Swarm deploy orchestrator з versioned Docker secrets (env payload, DB, RabbitMQ)
- ✅ Smart Elasticsearch index guard при deploy на порожньому volume
- ✅ `search-prefs` + `api-prefs` bootstrap модулі (SearchEngine, RESTBasicAuth)
- ✅ Backup offsite через rclone + окремий retention + textfile metrics
- ✅ `test-restore.sh` — restore smoke-test у тимчасову MariaDB (не торкає prod)
- ✅ `init-volumes.sh` ініціалізує `BACKUP_PATH` з ownership/ACL
- 🔄 CSP enforcement: `report-only` режим, tuning в прогресі

---

**Версія документу:** 2026 Q2  
**Останнє оновлення:** 2026-05-17  
**Status:** ✅ Production Ready
