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
    - інтеграто рів (API, integrations, customization points).
