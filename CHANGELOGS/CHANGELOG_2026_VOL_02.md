# CHANGELOG Volume 02 (2026)

Анотація:
- Контекст: продовження blocking-кроків після закриття `1.2`, перехід до `1.3 Identity/OIDC lockdown`.
- Зміст: поетапне впровадження OIDC-lockdown, перевірки й фіксація operational guardrails.

---

## 2026-03-01

### 1) Roadmap 1.3 (поетапно): крок 1/3 `disable local password reset/change`

- Додано операційний скрипт:
  - [scripts/koha-lockdown-password-prefs.sh](/home/pinokew/Koha/koha-deploy/scripts/koha-lockdown-password-prefs.sh)
  - застосовує в Koha:
    - `OpacResetPassword=0`
    - `OpacPasswordChange=0`
  - підтримує режими:
    - `--apply`
    - `--verify`
    - default: `apply + verify`

- Застосовано на поточному середовищі (факт):
  - `./scripts/koha-lockdown-password-prefs.sh`
  - `./scripts/koha-lockdown-password-prefs.sh --verify`

- Перевірено (факт):
  - `OpacPasswordChange=0`
  - `OpacResetPassword=0`

- Примітка:
  - це закриває саме підпункт `1.3.1` roadmap;
  - підпункти `1.3.2` і `1.3.3` виконуються окремими наступними кроками.

### 2) Roadmap 1.5 (частина 1): централізований збір логів у `VOL_KOHA_LOGS`

- Без розгортання додаткових сервісів додано host-скрипт збору контейнерних логів:
  - [scripts/collect-docker-logs.sh](/home/pinokew/Koha/koha-deploy/scripts/collect-docker-logs.sh)
  - джерело: `docker compose logs`
  - призначення: `${VOL_KOHA_LOGS}/centralized/docker/*.log`
  - state-файл інкрементального збору: `${VOL_KOHA_LOGS}/centralized/.docker_logs_since`

- Додано опційні env-параметри в:
  - [.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - `LOG_EXPORT_ROOT`, `LOG_STATE_FILE`, `LOG_FIRST_SINCE`

- Факт виконання:
  - `./scripts/collect-docker-logs.sh --dry-run`
  - `./scripts/collect-docker-logs.sh`
  - створено файли логів для всіх сервісів в одному місці:
    - `db.log`, `es.log`, `koha.log`, `memcached.log`, `rabbitmq.log`, `tunnel.log`

- Перевірено:
  - каталоги та файли створені під `VOL_KOHA_LOGS=/srv/koha-volumes/koha_logs`
  - інкрементальний стан оновлюється у `.docker_logs_since`

### 4) Roadmap 1.1 (поетапно): крок 2/4 + 3/4 + 4/4 (CI checks, pinned uses, permissions/concurrency)

- З урахуванням нового правила (UI-first) прибрано API-скрипт для branch protection:
  - видалено `scripts/apply-branch-protection.sh`
  - branch protection керується через GitHub UI/rulesets.

- Створено єдиний workflow:
  - [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)
  - jobs/checks:
    - `hadolint`
    - `shellcheck`
    - `trivy config`
    - `trivy image`
    - `secret-scan`

- Для critical workflow pinned `uses`:
  - `actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332`

- Мінімізація прав і керування паралельністю:
  - top-level `permissions: contents: read`
  - top-level `concurrency` з `cancel-in-progress: true`

- Важливо:
  - старий `.github/workflows/secret-scan.yml` видалено і замінено на consolidated workflow.

- Перевірено:
  - `actionlint` для нового workflow: без помилок.
  - локальні pre-check скрипти проходять:
    - `check-secrets-hygiene.sh`
    - `check-internal-ports-policy.sh`

### 5) Roadmap 1.1 (уточнення CI): 2 required jobs у `ci-cd-checks.yml`

- `ci-cd-checks.yml` перебудовано під 2 jobs для зручного ruleset-mapping:
  - `ci-checks`
  - `build-and-publish`

- У `ci-checks` зібрано основні gate-перевірки:
  - `hadolint`
  - `shellcheck`
  - `trivy config`
  - `check-secrets-hygiene.sh`
  - `check-internal-ports-policy.sh`
  - `gitleaks`

- У `build-and-publish` додано обмеження publish лише для `main`:
  - `if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main' && github.repository_owner == 'pinokew'`

- Pinned `uses` для critical action:
  - `actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332`

- Для required workflow не використовується `paths-ignore` (щоб уникати пропущених required checks на PR).

- Імплементовано корисні практики з `build-and-push.yml`:
  - `timeout-minutes` для jobs
  - `persist-credentials: false`, `fetch-depth: 1`
  - `workflow_dispatch`
  - pre-push `trivy image` scan
  - Buildx cache (`type=gha`)
  - генерація SBOM (`syft`, SPDX JSON)

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить без помилок.
  - Примітка: окремий файл `build-and-push.yml` має власну pre-existing синтаксичну проблему (`uses: *trivy_action`) і потребує окремого виправлення.
