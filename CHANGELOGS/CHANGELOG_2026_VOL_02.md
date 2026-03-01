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

### 3) Roadmap 1.1 (поетапно): крок 1/4 `branch protection для main`

- Додано скрипт застосування branch protection через GitHub API:
  - [scripts/apply-branch-protection.sh](/home/pinokew/Koha/koha-deploy/scripts/apply-branch-protection.sh)
  - покриває:
    - заборону force-push/delete
    - required review (мінімум 1)
    - required status checks
    - conversation resolution + linear history

- Перевірено локально:
  - `./scripts/apply-branch-protection.sh --dry-run`
  - payload формується коректно для `pinokew/koha-deploy:main`

- Обмеження поточного середовища:
  - `GITHUB_TOKEN` не заданий, тому `--apply` не виконувався в цій сесії.

- Команда застосування (коли є токен з admin правами на repo):
  - `GITHUB_TOKEN=*** ./scripts/apply-branch-protection.sh --apply`
