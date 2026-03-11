# 🏗️ [Project Name]

> **Одне речення — суть проєкту.** Наприклад: _Мікросервісна платформа для обробки платежів у реальному часі._

[![Status](https://img.shields.io/badge/status-active-brightgreen)]()
[![Version](https://img.shields.io/badge/version-1.0.0-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Security](https://img.shields.io/badge/security-audited-blueviolet)]()
[![Coverage](https://img.shields.io/badge/coverage-87%25-yellowgreen)]()

---

## 📋 Зміст

- [Поточний статус](#-поточний-статус)
- [Про проєкт](#-про-проєкт)
- [Архітектура стеку](#-архітектура-стеку)
- [Топологія репозиторію](#-топологія-репозиторію)
- [Топологія системи](#-топологія-системи)
- [Середовища](#-середовища)
- [Безпека](#-безпека)
- [Локальний запуск](#-локальний-запуск)
- [Деплой](#-деплой)
- [API & Інтеграції](#-api--інтеграції)
- [Моніторинг & Алерти](#-моніторинг--алерти)
- [Команда & Контакти](#-команда--контакти)
- [Ченджлог](#-ченджлог)

---

## 🚦 Поточний статус

> Цей розділ оновлюється при кожному значному релізі або зміні стану системи.

| Параметр | Значення |
|---|---|
| **Поточна версія** | `v1.2.0` |
| **Стадія** | `Beta / Production / Deprecated` |
| **Останній реліз** | `2025-03-01` |
| **Наступний мілстоун** | `v1.3.0` → [Roadmap](#) |
| **Uptime (30d)** | `99.7%` |
| **Відомі критичні баги** | `0` ([Issues](#)) |
| **Технічний борг** | 🟡 Середній — [деталі в Jira/Linear](#) |

### Що зараз в роботі
- [ ] Міграція БД на PostgreSQL 16
- [ ] Впровадження rate limiting на API Gateway
- [ ] Рефакторинг auth-сервісу

### Відомі обмеження
- `POST /api/v1/reports` — деградація при > 10k записів (workaround: пагінація)
- Відсутня підтримка Safari < 16

---

## 🎯 Про проєкт

### Проблема та рішення
Опишіть: яку бізнес-проблему вирішує проєкт, хто кінцевий користувач, які ключові обмеження були враховані при проєктуванні.

### Ключові можливості
- **Функція A** — короткий опис
- **Функція B** — короткий опис
- **Функція C** — короткий опис

### Що НЕ входить у скоуп
- Функціональність X (відповідає інший сервіс — [посилання](#))
- Функціональність Y (заплановано в Q3 2025)

---

## ⚙️ Архітектура стеку

### Зведена таблиця технологій

| Шар | Технологія | Версія | Призначення |
|---|---|---|---|
| **Frontend** | React | 18.x | SPA, клієнтський UI |
| **BFF** | Next.js | 14.x | SSR, API routes, edge caching |
| **Backend** | NestJS | 10.x | REST/gRPC бізнес-логіка |
| **База даних** | PostgreSQL | 15.x | Основне сховище |
| **Кеш** | Redis | 7.x | Сесії, черги, rate limiting |
| **Черга подій** | RabbitMQ | 3.12 | Async-комунікація між сервісами |
| **Об'єктне сховище** | AWS S3 | — | Файли, артефакти, бекапи |
| **CDN** | CloudFront | — | Статика, edge caching |
| **Контейнеризація** | Docker + K8s | 1.29 | Оркестрація |
| **CI/CD** | GitHub Actions | — | Пайплайни |
| **IaC** | Terraform | 1.7 | Інфраструктура як код |
| **Моніторинг** | Grafana + Prometheus | — | Метрики, дашборди |
| **Логування** | ELK Stack | 8.x | Централізовані логи |
| **Трейсинг** | OpenTelemetry + Jaeger | — | Distributed tracing |
| **Auth** | Keycloak | 23.x | SSO, OAuth2, OIDC |

### Принципи архітектури
- **Стиль**: Мікросервіси / Модульний моноліт / Event-Driven
- **Патерни**: CQRS, Saga, Circuit Breaker, Strangler Fig
- **Комунікація**: REST (sync), gRPC (internal sync), RabbitMQ (async)
- **Консистентність даних**: Eventual consistency через event sourcing

### Схема взаємодії компонентів

```
                        ┌─────────────────────────────────────────────┐
                        │                  CLIENTS                    │
                        │   Browser (React)   Mobile App   3rd Party  │
                        └──────────────┬───────────────────┬──────────┘
                                       │ HTTPS             │ HTTPS/API Key
                        ┌──────────────▼───────────────────▼──────────┐
                        │           API GATEWAY (Kong / AWS ALB)       │
                        │     Auth · Rate Limiting · Load Balancing    │
                        └──────────────┬──────────────────────────────┘
                ┌────────────┬─────────┴──────────┬────────────┐
                │            │                    │            │
         ┌──────▼──┐  ┌──────▼──┐         ┌──────▼──┐  ┌─────▼────┐
         │ Service │  │ Service │         │ Service │  │  BFF /   │
         │  Auth   │  │ Orders  │         │ Notif.  │  │ Next.js  │
         └──────┬──┘  └──────┬──┘         └──────┬──┘  └──────────┘
                │            │                    │
         ┌──────▼────────────▼──────────────────────────┐
         │              Message Broker (RabbitMQ)        │
         └──────────────────────────────────────────────┘
                │            │                    │
         ┌──────▼──┐  ┌──────▼──┐         ┌──────▼──┐
         │PostgreSQL│  │  Redis  │         │   S3    │
         └─────────┘  └─────────┘         └─────────┘
```

---

## 🗂️ Топологія репозиторію

> Детальний опис структури директорій — що де лежить і за що відповідає.

```
project-root/
│
├── 📁 apps/                        # Усі застосунки (monorepo)
│   ├── web/                        # React SPA
│   │   ├── src/
│   │   │   ├── components/         # Перевикористовувані UI-компоненти
│   │   │   ├── pages/              # Сторінки (маршрутизація)
│   │   │   ├── features/           # Feature-слайси (Redux Toolkit)
│   │   │   ├── hooks/              # Кастомні React hooks
│   │   │   ├── services/           # API-клієнти (axios instances)
│   │   │   └── utils/              # Загальні утиліти
│   │   ├── public/                 # Статичні ресурси
│   │   └── Dockerfile
│   │
│   ├── api/                        # NestJS Backend
│   │   ├── src/
│   │   │   ├── modules/            # Бізнес-модулі (users, orders, …)
│   │   │   │   └── [module]/
│   │   │   │       ├── dto/        # Data Transfer Objects + валідація
│   │   │   │       ├── entities/   # TypeORM сутності (схема БД)
│   │   │   │       ├── *.controller.ts   # HTTP/gRPC ендпоінти
│   │   │   │       ├── *.service.ts      # Бізнес-логіка
│   │   │   │       └── *.repository.ts   # Шар доступу до даних
│   │   │   ├── common/             # Декоратори, guards, фільтри, interceptors
│   │   │   ├── config/             # Конфігурація (ENV-схеми через Joi/Zod)
│   │   │   └── database/
│   │   │       └── migrations/     # TypeORM міграції (версіоновані)
│   │   └── Dockerfile
│   │
│   └── worker/                     # Фонові задачі та обробники черг
│       ├── src/
│       │   ├── consumers/          # RabbitMQ message handlers
│       │   ├── processors/         # Bull job processors
│       │   └── schedulers/         # Cron-задачі
│       └── Dockerfile
│
├── 📁 packages/                    # Shared бібліотеки (internal)
│   ├── ui-kit/                     # Спільні UI-компоненти (Storybook)
│   ├── types/                      # Спільні TypeScript типи та інтерфейси
│   ├── utils/                      # Утиліти, що шеряться між застосунками
│   └── config/                     # Спільні конфіги (ESLint, TSConfig, …)
│
├── 📁 infra/                       # Інфраструктура як код
│   ├── terraform/
│   │   ├── modules/                # Terraform-модулі (vpc, rds, eks, …)
│   │   ├── environments/
│   │   │   ├── dev/                # Стейт і змінні для dev
│   │   │   ├── staging/
│   │   │   └── prod/
│   │   └── main.tf
│   └── k8s/                        # Kubernetes manifests
│       ├── base/                   # Kustomize base
│       └── overlays/               # Env-специфічні оверлеї
│           ├── dev/
│           ├── staging/
│           └── prod/
│
├── 📁 .github/                     # GitHub-специфічне
│   ├── workflows/                  # CI/CD пайплайни
│   │   ├── ci.yml                  # Lint, тести, build
│   │   ├── cd-staging.yml          # Деплой на staging (auto)
│   │   └── cd-prod.yml             # Деплой на prod (manual approve)
│   ├── CODEOWNERS                  # Відповідальні за review по директоріях
│   ├── pull_request_template.md
│   └── ISSUE_TEMPLATE/
│
├── 📁 docs/                        # Технічна документація
│   ├── adr/                        # Architecture Decision Records
│   │   └── 001-use-rabbitmq.md
│   ├── api/                        # OpenAPI специфікації
│   ├── diagrams/                   # C4, ER, sequence діаграми (PlantUML/Mermaid)
│   └── runbooks/                   # Операційні процедури (інцидент-менеджмент)
│
├── 📁 scripts/                     # Dev/ops утилітні скрипти
│   ├── setup.sh                    # Первинне налаштування середовища
│   ├── seed.sh                     # Заповнення БД тестовими даними
│   └── migrate.sh                  # Обгортка над міграціями
│
├── docker-compose.yml              # Локальний запуск усіх сервісів
├── docker-compose.override.yml     # Локальні оверайди (hot reload, debug ports)
├── .env.example                    # Шаблон змінних середовища
├── turbo.json                      # Turborepo конфігурація (якщо monorepo)
├── package.json                    # Root package.json (workspaces)
└── README.md                       # Цей файл ← ви тут
```

### Ключові файли та їх роль

| Файл / Директорія | Власник | Призначення |
|---|---|---|
| `infra/terraform/` | DevOps | Вся хмарна інфраструктура |
| `infra/k8s/` | DevOps | K8s-деплойменти, сервіси, ingress |
| `apps/api/src/database/migrations/` | Backend Lead | Версіонування схеми БД |
| `packages/types/` | Tech Lead | Контракт між сервісами |
| `docs/adr/` | Всі | Рішення архітектури з обґрунтуванням |
| `.github/CODEOWNERS` | Tech Lead | Матриця відповідальності за код |
| `.env.example` | DevOps | Документація всіх ENV змінних |

---

## 🌍 Середовища

| Середовище | URL | Гілка | Деплой | Призначення |
|---|---|---|---|---|
| **Local** | `localhost:3000` | будь-яка | `docker compose up` | Розробка |
| **Dev** | `dev.project.com` | `develop` | Автоматично | Інтеграція |
| **Staging** | `staging.project.com` | `main` | Автоматично | QA / UAT |
| **Production** | `project.com` | `main` + tag | Ручно (approve) | Живий трафік |

### Конфігурація середовищ
Усі ENV змінні задокументовані у `.env.example`. Секрети зберігаються в **AWS Secrets Manager / HashiCorp Vault** і підтягуються під час деплою — **ніколи** не комітьте `.env` файли.

---

## 🔒 Безпека

### Модель загроз
Ключові активи: персональні дані користувачів, платіжні дані, токени доступу.
Основні вектори ризику: OWASP Top 10, Supply Chain, Credential Leakage.

### Автентифікація та авторизація

| Механізм | Реалізація | Де застосовується |
|---|---|---|
| **SSO / OIDC** | Keycloak | Зовнішні користувачі |
| **JWT** | RS256, TTL 15 хв | API авторизація |
| **Refresh Token** | HTTP-only Cookie, TTL 7d | Поновлення сесії |
| **API Key** | SHA-256 hash у БД | Machine-to-machine |
| **RBAC** | Ролі: `admin`, `manager`, `viewer` | Бізнес-логіка |
| **mTLS** | Istio Service Mesh | Internal сервіс-до-сервісу |

### Захист даних

- **At rest**: AES-256 шифрування для PII полів (TypeORM Subscribers)
- **In transit**: TLS 1.3 на всіх ендпоінтах; HSTS увімкнено
- **Secrets**: AWS Secrets Manager; ротація кожні 90 днів
- **PII**: Маскування в логах (custom Winston formatter); GDPR compliant
- **Backup**: Щоденні snapshot RDS з 30-денним retention; перевірка restore щомісяця

### Мережева безпека

```
Internet → WAF (AWS Shield + CloudFront) → ALB → API Gateway → Services
                                                       ↓
                                              VPC Private Subnet
                                         (DB, Redis, RabbitMQ — без публічного IP)
```

- VPC з публічними та приватними підмережами
- Security Groups: принцип least privilege
- NACLs як додатковий шар
- Private endpoints для AWS-сервісів (без NAT)

### SAST / DAST / Залежності

| Інструмент | Тип | Коли запускається |
|---|---|---|
| `ESLint + security plugin` | SAST | Pre-commit, CI |
| `Semgrep` | SAST | CI (PR) |
| `Snyk / Dependabot` | SCA (залежності) | Щодня |
| `OWASP ZAP` | DAST | Після деплою на staging |
| `Trivy` | Container scan | CI (build image) |
| `tfsec` | IaC scan | CI (terraform) |

### Політики

- **Уразливості**: Critical — патч протягом 24h; High — 7 днів
- **Секрети в коді**: Автоматичне блокування через `gitleaks` pre-commit hook
- **Security Review**: Обов'язковий для будь-яких змін в auth, payments, PII
- **Penetration Testing**: Раз на рік (зовнішній підрядник)
- **Incident Response Runbook**: [`docs/runbooks/security-incident.md`](docs/runbooks/security-incident.md)

### Звітування про вразливості
Знайшли вразливість? **Не створюйте публічний issue.**
Надішліть деталі на: `security@project.com` (GPG key: [посилання](#))

---

## 🚀 Локальний запуск

### Передумови

| Інструмент | Мінімальна версія | Перевірка |
|---|---|---|
| Node.js | 20.x LTS | `node -v` |
| Docker | 24.x | `docker -v` |
| Docker Compose | 2.x | `docker compose version` |
| Git | 2.40+ | `git --version` |

### Швидкий старт

```bash
# 1. Клонування
git clone git@github.com:org/project.git && cd project

# 2. Налаштування змінних середовища
cp .env.example .env
# Відредагуйте .env — мінімальний набір позначений як REQUIRED

# 3. Запуск інфраструктури та сервісів
docker compose up -d

# 4. Міграції та seed
npm run db:migrate
npm run db:seed        # опціонально, тестові дані

# 5. Запуск у dev-режимі (hot reload)
npm run dev
```

Після цього:
- Frontend: http://localhost:3000
- API: http://localhost:4000
- API Docs (Swagger): http://localhost:4000/api/docs
- RabbitMQ Management: http://localhost:15672 (guest/guest)
- Grafana: http://localhost:3001 (admin/admin)

### Часті проблеми

<details>
<summary>Порт 5432 вже зайнятий</summary>

```bash
# Знайти та зупинити процес
lsof -i :5432
# Або змінити порт у .env: POSTGRES_PORT=5433
```
</details>

<details>
<summary>Помилка міграцій</summary>

```bash
npm run db:migrate:revert  # відкат останньої міграції
npm run db:migrate         # повторний запуск
```
</details>

---

## 📦 Деплой

### CI/CD Пайплайн

```
Push / PR → Lint & Type Check → Unit Tests → Build → Docker Build & Scan
                                                              ↓
                                                    Push to ECR Registry
                                                              ↓
                                              ┌───── Staging (auto) ──────┐
                                              │  Smoke Tests · DAST Scan  │
                                              └──────────┬────────────────┘
                                                         │ Manual Approve
                                                    ┌────▼─────┐
                                                    │   PROD   │
                                                    └──────────┘
```

### Ручний деплой на prod

```bash
# Тільки через GitHub Actions workflow!
# gh CLI:
gh workflow run cd-prod.yml -f version=v1.2.0
```

### Rollback

```bash
# K8s rollback до попередньої версії
kubectl rollout undo deployment/api -n production

# Або через GitHub Actions: запустіть workflow з попереднім тегом
```

---

## 🔌 API & Інтеграції

### Документація API
- **Swagger UI**: `/api/docs` (staging: [посилання](#))
- **OpenAPI spec**: [`docs/api/openapi.yaml`](docs/api/openapi.yaml)
- **Postman Collection**: [`docs/api/postman_collection.json`](docs/api/postman_collection.json)

### Зовнішні інтеграції

| Сервіс | Призначення | Власник | Docs |
|---|---|---|---|
| Stripe | Платежі | @payments-team | [посилання](#) |
| SendGrid | Email-нотифікації | @backend-team | [посилання](#) |
| Twilio | SMS | @backend-team | [посилання](#) |
| Google Maps API | Геокодування | @frontend-team | [посилання](#) |

### Версіонування API
API версіонується через URL prefix: `/api/v1/`, `/api/v2/`.
Старі версії підтримуються 6 місяців після виходу нової.

---

## 📊 Моніторинг & Алерти

### Дашборди

| Дашборд | Інструмент | Посилання |
|---|---|---|
| Загальний стан системи | Grafana | [посилання](#) |
| Помилки та трейси | Jaeger | [посилання](#) |
| Логи | Kibana | [посилання](#) |
| Uptime | Uptime Robot | [посилання](#) |

### Ключові метрики (SLI/SLO)

| Метрика | SLO | Алерт при |
|---|---|---|
| API Availability | ≥ 99.5% | < 99% за 5 хв |
| P95 Response Time | ≤ 500ms | > 1s за 10 хв |
| Error Rate | ≤ 1% | > 5% за 5 хв |
| DB Connection Pool | ≤ 80% | > 90% |

### On-call

Ескалація та on-call розклад: [PagerDuty / OpsGenie](#)
Runbooks для типових інцидентів: [`docs/runbooks/`](docs/runbooks/)

---

## 👥 Команда & Контакти

| Роль | Ім'я | GitHub | Зона відповідальності |
|---|---|---|---|
| Tech Lead | Іван Петренко | @ivanp | Архітектура, code review, ADR |
| Backend Lead | Оксана Коваль | @okoval | API, БД, мікросервіси |
| Frontend Lead | Дмитро Мороз | @dmitm | UI, BFF, performance |
| DevOps | Сергій Бондар | @sbond | Infra, CI/CD, Security |
| QA Lead | Ліна Шевченко | @lshev | Тест-стратегія, автотести |

**Slack-канали**: `#proj-dev` · `#proj-alerts` · `#proj-releases`

---

## 📜 Ченджлог

> Детальний ченджлог: [`CHANGELOG.md`](CHANGELOG.md). Тут — тільки останні релізи.

### v1.2.0 — 2025-03-01
- ✅ Додано підтримку OAuth2 через Google
- ✅ Rate limiting на рівні API Gateway
- 🐛 Виправлено memory leak у workers під навантаженням

### v1.1.0 — 2025-01-15
- ✅ Переїзд на PostgreSQL 15
- ✅ Впровадження OpenTelemetry трейсингу

---

## 📚 Додаткові ресурси

- [Architecture Decision Records](docs/adr/)
- [Onboarding Guide для нових розробників](docs/onboarding.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [License](LICENSE)

---

<div align="center">
  <sub>Останнє оновлення README: 2025-03-11 · Власник документа: <a href="#">Tech Lead</a></sub>
</div>
