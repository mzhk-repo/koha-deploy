# 🏆 Koha Deploy – Production Library Stack

> **Вичерпна операційна документація для production-стеку Koha Library Management System.**  
> Оркестровано Docker Compose, керовано через env-SSOT, розгортається через безпечний CI/CD.

[![Статус](https://img.shields.io/badge/status-production-brightgreen)]()
[![Версія](https://img.shields.io/badge/version-2026_Q1-blue)]()
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
| **Поточна версія** | `2026 Q1` (Roadmap Hardening v2) |
| **Стадія** | **Production** |
| **Останній реліз** | 2026-03-03 |
| **Наступний мілстоун** | Observability enhancement (Roadmap 2.1) |
| **Відомі критичні баги** | `0` → [Issues](ROADMAP_PROD.md) |
| **Технічний борг** | 🟡 **Середній** — див. [ROADMAP_PROD.md](ROADMAP_PROD.md#-performance-baseline) |

### Активні ініціативи

- ✅ Базова безпека та хардeнінг (Roadmap 1.1–1.4): **CLOSED**
- 🔄 Спостережуваність (_Observability_): **IN PROGRESS**
  - Логування централізовано, метрики базові
  - Планується: розподілене трасування, алерти
- ⏸️ Performance baseline: **SCHEDULED**
  - Передбачається: MariaDB tuning, Product analytics, SLO-driven metrics

### Що саме було закрито

1. **Секрети таCI/CD**: обов'язкові перевірки на `main` (gitleaks, secret-scan, shellcheck, hadolint).
2. **Runtime hardening**: `security_opt`, `cap_drop`, memory/cpu limits для всіх сервісів.
3. **Identity lockdown**: OPAC password reset заблокована.
4. **Supply-chain**: базові SBOM + Trivy config gate.
5. **Backup/Restore**: full-featured з dry-run, PITR, автоматичний ES rebuild.
6. **CI/CD deploy**: автоматичний деплой на `main` через SSH.

### Відомі обмеження

- Elasticsearch 8.x без x-pack (для production рекомендується x-pack authentication).
- Product analytics ще не розгорнута (GA4/Matomo в планах).
- Розподілене трасування (Jaeger/Tempo) ще не інтегровано.

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
| **Secure Access (Cloudflare Tunnel)** | Зовнішній доступ без відкриття портів напряму |
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
| **Web Framework** | Koha | 24.x | Система управління бібліотекою |
| **Web Server** | Plack/Apache2 | modern | HTTP-сервер, Load balancing |
| **База даних** | MariaDB | 11.x | Основне сховище даних |
| **Search Engine** | Elasticsearch | 8.19.6 | Індексація та пошук |
| **Кеш** | Memcached | 1.6.x | Session storage, cache layer |
| **Черга подій** | RabbitMQ | 3.x | Message broker для async-операцій |
| **Контейнеризація** | Docker + Compose | latest | Оркестрація сервісів |
| **Access Control** | Cloudflare Tunnel | 2026.2.0 | Зовнішній доступ без portforward |
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
    │         (через Cloudflare Tunnel)                      │
    └────────────────────┬────────────────────────────────────┘
                         │ HTTPS
    ┌────────────────────▼────────────────────────────────────┐
    │      cloudflared tunnel ← Cloudflare (SAT)             │
    │    (localhost:8080 OPAC, localhost:8081 Intranet)     │
    └────────────────────┬────────────────────────────────────┘
                         │ internal kohanet
    ┌────────────────────▼────────────────────────────────────┐
    │  KOHA (Plack/Apache)                                   │
    │  - biblios, users, circulation, reporting              │
    │  - Health check: http://koha:8081 (intranet)          │
    └────────┬───────────┬────────────┬──────────────────────┘
             │           │            │
      ┌──────▼──┐  ┌────▼────┐  ┌───▼────┐
      │  MariaDB │  │RabbitMQ │  │  ES    │
      │  (db)    │  │ (queue) │  │ (8.x)  │
      └──────────┘  └────┬────┘  └────────┘
                         │
                    ┌────▼──────┐
                    │ Memcached  │
                    │ (cache)    │
                    └────────────┘

    All services in 'kohanet' isolated network
    No host-published ports (except tunnel ingress)
    Resource-limited: CPU/memory/pids/ulimits
```

---

## 🗂️ Топологія репозиторію

```
koha-deploy/
│
├── 📄 docker-compose.yaml              # Основна оркестрація сервісів
├── 📄 .env.example                     # Шаблон конфігурації (SSOT)
├── 📄 .gitignore                       # git-фільтри (крім .env)
│
├── 📁 scripts/                         # Операційні скрипти (bash)
│   ├── verify-env.sh                   # Валідація .env перед запуском
│   ├── bootstrap-live-configs.sh       # Оркестратор live-патчів Koha
│   ├── test-smtp.sh                    # Runtime SMTP перевірка
│   ├── backup.sh                       # Full backup DB + volumes
│   ├── restore.sh                      # Restore / PITR procedure
│   ├── collect-docker-logs.sh          # Збір логів з контейнерів
│   ├── install-collect-logs-timer.sh   # Встановлення systemd timer
│   ├── check-secrets-hygiene.sh        # Secret scan у commit
│   ├── check-internal-ports-policy.sh  # Перевірка мережевої політики
│   │
│   └── 📁 patch/                       # Модулі live-конфігу
│       ├── _patch_common.sh            # Спільні утиліти
│       ├── patch-koha-conf-xml.sh      # Базова конфігурація
│       ├── patch-koha-conf-xml-memcached.sh  # Memcached інтеграція
│       ├── patch-koha-conf-xml-message-broker.sh # RabbitMQ інтеграція
│       ├── patch-koha-conf-xml-smtp.sh # SMTP конфіг
│       ├── patch-koha-conf-xml-timezone.sh    # Timezone setup
│       ├── patch-koha-conf-xml-verify.sh      # Верифікація XML
│       └── patch-koha-templates.sh     # HTML/CSS патчі
│
├── 📁 systemd/                         # Systemd service/timer
│   ├── koha-deploy-collect-logs.service
│   └── koha-deploy-collect-logs.timer
│
├── 📁 elasticsearch/                   # Local ES Dockerfile
│   └── Dockerfile
├── 📁 rabbitmq/                        # Local RabbitMQ Dockerfile
│   └── Dockerfile
├── 📁 memcached/                       # Local Memcached Dockerfile
│   └── Dockerfile
│
├── 📁 .github/workflows/               # CI/CD
│   └── ci-cd-checks.yml                # Lint, test, deploy workflow
│
├── 📁 CHANGELOGS/                      # Versioned changelog volumes
│   ├── CHANGELOG_2026_VOL_01.md
│   ├── CHANGELOG_2026_VOL_02.md
│   ├── CHANGELOG_2026_VOL_03.md
│   └── CHANGELOG_2026_VOL_04.md (active)
│
├── 📄 CHANGELOG.md                     # Changelog index
├── 📄 ROADMAP_PROD.md                  # Development roadmap & priorities
├── 📄 ARCHITECTURE.md                  # Архітектурні правила & обмеження
├── 📄 RUNBOOK_DR.md                    # Disaster Recovery procedures
├── 📄 AGENTS.md                        # New session start guide
├── 📄 README.md                        # **ВИ ТУТАМО** (це файл)
└── 📄 README.example.md                # Template for new projects
```

---

## 🏗️ Топологія системи (docker-compose)

### Сервіси та їхні ролі

| Сервіс | Образ | Назначення | Порти (внутрішні) | Health Check |
|---|---|---|---|---|
| **koha** | ext. registry | Web-додаток Koha (Plack) | 8080 (OPAC), 8081 (Intranet) | HTTP 8081, 15s interval |
| **db** | `mariadb:11` | Реляційна БД | 3306 | mariadb-admin ping, 10s |
| **es** | local build | Elasticsearch search | 9200 | curl http://9200, 10s |
| **rabbitmq** | local build | Message queue, async | 5672 (AMQP), 61613 (STOMP), 15672 (mgmt) | rabbitmq-diagnostics ping |
| **memcached** | local build | Розподілений кеш | 11211 | TCP socket (auto) |
| **tunnel** | `cloudflare/cloudflared` | Зовнішній доступ | — | TCP keep-alive |

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
| **tunnel** | 128 MB (default) | 0.25 | 1024 |

> **Примітка**: Усі ліміти можуть бути перевизначені через `.env` змінні (e.g., `KOHA_MEM_LIMIT`, `DB_CPUS`).

---

## 🔧 Конфігураційна модель

### SSOT (Single Source of Truth)

Вся runtime-конфігурація керується трьома файлами:

1. **`.env.example`** — еталонний шаблон з усіма змінними та їхніми описами
2. **`.env`** — локальна конфігурація (git-ignored, не комітиться)
3. **`docker-compose.yaml`** — сервіси та обробники, що читають з `.env`

### Ключові категорії змінних

| Категорія | Приклади | Де зберігається |
|---|---|---|
| **Koha Config** | `KOHA_INSTANCE`, `KOHA_DOMAIN`, `KOHA_TIMEZONE` | `.env` |
| **Database** | `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_ROOT_PASS` | `.env` (secret) |
| **Elasticsearch** | `ELASTICSEARCH_HOST`, `USE_ELASTICSEARCH` | `.env` |
| **RabbitMQ** | `RABBITMQ_USER`, `RABBITMQ_PASS`, `MB_HOST`, `MB_PORT` | `.env` (secret) |
| **Memcached** | `MEMCACHED_SERVERS` | `.env` |
| **Cloudflare** | `CLOUDFLARE_TOKEN` | `.env` (secret) |
| **SMTP** | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_SSL_MODE` | `.env` (secret) |
| **Volume Paths** | `VOL_DB_PATH`, `VOL_KOHA_CONF`, `VOL_KOHA_DATA` | `.env` |
| **Resource Limits** | `KOHA_MEM_LIMIT`, `DB_CPUS`, `ES_MEM_LIMIT` | `.env` |
| **Logging** | `LOG_MAX_SIZE`, `LOG_MAX_FILE` | `.env` |

### Live-конфіг патчі

Сервіс Koha має `koha-conf.xml`, який може змінюватися runtime. Для цього використовується модульна система патчів:

```bash
# Усі модулі
bash scripts/bootstrap-live-configs.sh --all

# Вибіркові модулі
bash scripts/bootstrap-live-configs.sh --modules smtp,memcached

# Список підтримуваних модулів
bash scripts/bootstrap-live-configs.sh --help
```

**Модулі (в `scripts/patch/`):**
- `patch-koha-conf-xml.sh` — базова Koha конфігурація
- `patch-koha-conf-xml-memcached.sh` — Memcached інтеграція
- `patch-koha-conf-xml-message-broker.sh` — RabbitMQ інтеграція
- `patch-koha-conf-xml-smtp.sh` — SMTP параметри
- `patch-koha-conf-xml-timezone.sh` — Часовий пояс
- `patch-koha-templates.sh` — Frontend HTML/CSS патчі

---

## 🔒 Безпека

### Security-First Принципи

| Принцип | Реалізація |
|---|---|
| **Secrets не комітяться** | `.env` в `.gitignore`; CI checks блокують розповсюджування |
| **Least Privilege** | `cap_drop: ALL`, `security_opt: no-new-privileges`, мінімальні UNIX-права |
| **Network Isolation** | Єдина внутрішня docker-мережа; немає published host ports |
| **Access via Tunnel** | Cloudflare Tunnel замість прямого port forwarding |
| **Container Hardening** | `pids_limit`, `ulimits`, memory/cpu limits, seccomp-profiles (можна додати) |
| **Logging Security** | Логи вивантажуються наприкінці; не залишаються в контейнері |
| **Image Scanning** | Триви config gate в CI; рекомендовано image scan |
| **Identity Lockdown** | OPAC password reset вимкнено (`OpacResetPassword=0`) |

### Secrets Management

**Недопустимо (❌):**
- Комітити `.env` з реальними значеннями
- Зберігати паролі в `docker-compose.yaml`

**Допустимо (✅):**
- Використовувати `.env.example` як еталон
- Передавати secrets через CI/CD secrets (GitHub Secrets)
- Ротація паролів за розписанням
- Аудит доступу до `.env`

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

2. **Скопіювати шаблон конфігурації:**
   ```bash
   cp .env.example .env
   ```

3. **Редагувати `.env`** під ваше оточення:
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
   
   # Для локального запуску Cloudflare Tunnel не потрібен
   # (залишити пусто або використовувати mock)
   CLOUDFLARE_TOKEN=
   
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
koha-tunnel-1  cloudflare/cloudflared  Up
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

**Локально (без Cloudflare Tunnel):**
```bash
# OPAC (public catalog)
http://localhost:8080/

# Intranet (staff interface)  – потребує входу
http://localhost:8081/
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
bash scripts/backup.sh
```

**Обов'язково перевіряє:**
- Наявність директорій томів
- Доступність DB
- Достатньо місця на диску
- Контрольні суми (для перевірки цілісності)

**Результат:**
```
backup_<timestamp>.tar.gz           # Архів (у `.env` VOL__BACKUP_PATH)
backup_<timestamp>.tar.gz.sha256    # Контрольна сума
backup_<timestamp>.metadata.json    # Метадані backup
```

### Restore

**Dry-run (без особливих змін):**
```bash
bash scripts/restore.sh --dry-run --backup-file backup_<timestamp>.tar.gz
```

**Full restore (PITR):**
```bash
bash scripts/restore.sh --backup-file backup_<timestamp>.tar.gz
```

**Потім:**
```bash
docker compose up -d --build
bash scripts/bootstrap-live-configs.sh --all
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

> Детальніше див. [ARCHITECTURE.md](ARCHITECTURE.md#7-cicd-архітектура) і [RUNBOOK_DR.md](RUNBOOK_DR.md).

### Manual Deploy (на серверу)

**Передумови:**
- SSH доступ до сервера
- Git доступ до `main` branch
- Вміст `.env` на серверу налаштований

**Процедура:**

```bash
# SSH на сервер
ssh user@production.server
cd /opt/koha-deploy

# Оновити код
git fetch origin
git reset --hard origin/main

# Оновити сервіси
docker compose pull
docker compose build --no-cache
docker compose up -d --remove-orphans

# Застосувати конфіги
bash scripts/bootstrap-live-configs.sh --all

# Перевірити health
bash scripts/verify-env.sh
docker compose ps
```

### Automated Deploy (GitHub Actions)

Workflow: `.github/workflows/ci-cd-checks.yml`

**Trigger:** `push` на `main` branch

**Перевірки (CI):**
- Hadolint (Dockerfile linter)
- Shellcheck (bash linter)
- Docker Compose config validation
- Secret hygiene check (gitleaks)
- Internal ports policy check

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

### Cloudflare Tunnel не підключиться

```bash
# Перевірити токен
docker compose logs tunnel | grep -i error

# Перевірити connectivity
docker compose exec tunnel cloudflared tunnel info

# Restart tunnel
docker compose restart tunnel
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

1. **[AGENTS.md](AGENTS.md)** — guide для нової сесії
2. **[ROADMAP_PROD.md](ROADMAP_PROD.md)** — текущі пріоритети і що буде далі
3. **[ARCHITECTURE.md](ARCHITECTURE.md)** — правила & обмеження проєкту

### Для операцій та коли щось ламається

- **[RUNBOOK_DR.md](RUNBOOK_DR.md)** — Disaster Recovery процедури
- **[CHANGELOG.md](CHANGELOG.md)** − індекс змін (у томах у `CHANGELOGS/`)

### Для розробленння та fork'ів

- **README.example.md** — template для новых проектів (не редагувати)
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

> Див. [CHANGELOG.md](CHANGELOG.md) для індексу томів. Активний том: [CHANGELOG_2026_VOL_04.md](CHANGELOGS/CHANGELOG_2026_VOL_04.md)

**Останні оновлення (краї Vol 04):**
- ✅ CI/CD workflow спрощено (fast-core checks)
- ✅ Trivy config gate додано
- ✅ README архітектурні деталі оновлено
- 🔄 Observability: логи, базові метрики готові; алерти в дорі

---

**Версія документу:** 2026 Q1  
**Останнє оновлення:** 2026-03-03  
**Status:** ✅ Production Ready
4. `CHANGELOG.md`

## Safety Notes

1. Do not commit real secrets to git.
2. Prefer image digest pin for `KOHA_IMAGE` in production.
3. Avoid manual in-container config edits as a permanent solution.
