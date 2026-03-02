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

- Додатковий фікс сумісності Trivy:
  - прибрано `--no-progress` з `trivy config` та `trivy image` у `ci-cd-checks.yml`,
    бо у поточному CLI Trivy це невалідний прапор (`unknown flag: --no-progress`).
  - після правки workflow знову проходить `actionlint`.
  - Примітка: окремий файл `build-and-push.yml` має власну pre-existing синтаксичну проблему (`uses: *trivy_action`) і потребує окремого виправлення.

### 6) CI fix: `shellcheck` fail у `ci-checks`

- Виправлено зауваження `shellcheck` у скриптах:
  - [backup.sh](/home/pinokew/Koha/koha-deploy/scripts/backup.sh)
    - `SC2053`: у `[[ ... == ... ]]` RHS зроблено quoted для точного match.
    - `SC2094`: генерація `SHA256SUMS` через тимчасовий файл + `mv`.
    - `SC2028`: заголовок маніфесту переведено з `echo` на `printf`.
  - [restore.sh](/home/pinokew/Koha/koha-deploy/scripts/restore.sh)
    - `SC2002`: прибрано `cat |`, імпорт SQL через input redirection.
    - `SC1091`: додано explicit directive для `pitr_master_status.env`.
    - `SC2086`: прибрано `awk '$0 >= s'` конструкцію, замінено на безпечний POSIX-цикл фільтрації binlog-файлів.
  - [patch-koha-templates.sh](/home/pinokew/Koha/koha-deploy/scripts/patch-koha-templates.sh)
    - `SC1090`: додано `shellcheck disable` directive для динамічного `.env` source.

- Перевірено:
  - запуском тієї ж команди, що в CI:
    - `docker run ... koalaman/shellcheck:v0.10.0 -x <scripts>`
  - результат: exit code `0` (помилки/попередження, що падали пайплайн, усунуті).

### 7) CI fix: видимі логи Trivy при `exit code 1`

- Оновлено [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml):
  - для `Trivy config` і `Trivy image` додано capture в лог-файли (`tee`):
    - `trivy-config.log`
    - `trivy-image.log`
  - кроки Trivy виконуються з `continue-on-error: true` + фіксація `exit_code` у `GITHUB_OUTPUT`.
  - додано окремі кроки `log tail` (`tail -n 200`) з `if: always()` для гарантованого виводу в GitHub Actions log.
  - додано окремі fail-gate кроки:
    - `Fail on Trivy config`
    - `Fail on Trivy image`
    які завершують job з помилкою, якщо `exit_code != 0`.

- Результат:
  - при падінні Trivy у GitHub одразу видно детальний вивід сканера;
  - статус job залишається blocking (pipeline не стає "green" при findings/error).

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить без помилок.
