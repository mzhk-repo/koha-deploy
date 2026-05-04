# CHANGELOG Volume 03 (2026)

Анотація:
- Контекст: продовження hardening CI/CD після завершення основного блоку roadmap 1.1.
- Зміст: тимчасове risk acceptance для Trivy у release-вікні та стабілізація підключення ignore-файлу в image scans.

---

## 2026-03-02

### 1) Тимчасовий ignore-list для Trivy з expiry/risk acceptance

- Додано файл:
  - [.trivyignore.yaml](/home/pinokew/Koha/koha-deploy/.trivyignore.yaml)

- Формат винятків приведено до YAML-шаблону як в `archive/.trivyignore.yaml`:
  - `vulnerabilities[].id`
  - `vulnerabilities[].expired_at`
  - `vulnerabilities[].statement`

- Додані тимчасові винятки з окремим `expired_at` для кожного ID:
  - `CVE-2025-68121`
  - `CVE-2025-58183`
  - `CVE-2025-61726`
  - `CVE-2025-61728`
  - `CVE-2025-61729`
  - `CVE-2025-61730`
  - `CVE-2025-68973`
  - `GHSA-72hv-8253-57qq`

- Важливо:
  - це тимчасовий захід для проходження релізного вікна;
  - після оновлення базових образів винятки мають бути прибрані.

### 2) Фікс: підключення `.trivyignore` у `Trivy image` кроці

- Оновлено workflow:
  - [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)

- Для `Trivy images` додано:
  - `-v "$PWD:/work"`
  - `-w /work`
  - `--ignorefile /work/.trivyignore.yaml`
  - `--scanners vuln`
  - `--cache-dir /trivy-cache` + mount `-v "${cache_dir}:/trivy-cache"`

- Результат:
  - YAML ignore-файл гарантовано застосовується в контейнері Trivy під час image scan;
  - кеш Trivy повторно використовується між сканами образів у межах job.

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить.

### 3) Централізація версій CI-утиліт у `env` + digest pin для hadolint

- У [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml) винесено image refs у top-level `env`:
  - `TRIVY_IMAGE`
  - `HADOLINT_IMAGE`
  - `SHELLCHECK_IMAGE`
  - `GITLEAKS_IMAGE`
  - `SYFT_IMAGE`

- Оновлено кроки на використання змінних з `env`:
  - Shellcheck
  - Gitleaks
  - SBOM (syft)

- `HADOLINT_IMAGE` запінено на digest:
  - `hadolint/hadolint@sha256:84c2f9088a8cb0ea2bd16b5349186770d16441e77eec1a1d1e0574cf7dff47ac`

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить.

### 4) Закриття зовнішньої публікації портів Koha (доступ тільки через Cloudflare Tunnel)

- Оновлено compose:
  - [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)

- У сервісі `koha` секцію `ports` закоментовано з поясненням:
  - host-публікація портів вимкнена;
  - зовнішній доступ тільки через сервіс `tunnel` (Cloudflare Tunnel).

- Застосування змін:
  - виконано `docker compose up -d koha tunnel` (recreate `koha`).

- Перевірено:
  - `docker compose config` — конфіг валідний;
  - `scripts/check-internal-ports-policy.sh` — policy проходить;
  - `docker compose ps` — у `koha` відсутні published порти `0.0.0.0:...`, залишилися лише внутрішні container ports;
  - health/services: `koha` у статусі `healthy`, інші сервіси стеку `up/healthy`;
  - data-check: не виконувався (зміна тільки мережевого експонування).

### 5) SMTP: env-конфігурація + автоматичне застосування + runtime тест

- Додано SMTP-змінні у SSOT env:
  - [.env](/home/pinokew/Koha/koha-deploy/.env)
  - [.env.example](/home/pinokew/Koha/koha-deploy/.env.example)

- Нові ключі:
  - `SMTP_HOST`, `SMTP_PORT`, `SMTP_TIMEOUT`, `SMTP_SSL_MODE`, `SMTP_USER_NAME`, `SMTP_PASSWORD`, `SMTP_DEBUG`
  - `SMTP_TEST_TO`, `SMTP_TEST_FROM`

- Додано скрипти:
  - [configure-smtp.sh](/home/pinokew/Koha/koha-deploy/scripts/configure-smtp.sh) — застосовує SMTP блок у `koha-conf.xml` з `.env`
  - [test-smtp.sh](/home/pinokew/Koha/koha-deploy/scripts/test-smtp.sh) — виконує пряму тестову SMTP-відправку через Koha Perl runtime (`C4::Context` + `Email::Sender`)

- Виконано:
  - `bash scripts/configure-smtp.sh`
  - `bash scripts/test-smtp.sh`

- Результат тесту:
  - fail: `unable to establish SMTP connection to (localhost) port 25`
  - тобто механізм налаштований і перевірка працює, але у поточному середовищі немає доступного SMTP relay на `localhost:25`.

- Перевірено:
  - `bash scripts/verify-env.sh` — OK
  - `koha-conf.xml` містить актуальний `<smtp_server>` блок;
  - services/health: стек працює (`koha` healthy), data-check не виконувався (зміни конфігураційні).


### 6) Видалення legacy `patch-koha-templates.sh` з deploy-потоку (підтверджено)

- Підтверджено рішення: `scripts/patch-koha-templates.sh` не використовується у цьому deploy-репо і видалений свідомо.

- Для узгодженості SSOT прибрано legacy env-ключі, що були прив'язані до цього скрипта:
  - `KOHA_OFFICIAL_TEMPLATES_DIR`
  - `KOHA_TARGET_TEMPLATES_DIR`

- Оновлено:
  - [.env](/home/pinokew/Koha/koha-deploy/.env)
  - [.env.example](/home/pinokew/Koha/koha-deploy/.env.example)

- Перевірено:
  - `bash scripts/verify-env.sh` — OK;
  - активних посилань на `patch-koha-templates.sh` в робочих файлах не залишилось (є лише історичний запис в archived changelog томі).


### 7) Повернення env-змінних для template patch flow (scripts/patch)

- Після уточнення, що `patch-koha-templates.sh` потрібен і перенесений у:
  - `scripts/patch/patch-koha-templates.sh`
  повернуто змінні в обидва env-файли.

- Повернуті ключі:
  - `KOHA_OFFICIAL_TEMPLATES_DIR`
  - `KOHA_TARGET_TEMPLATES_DIR`

- Оновлено:
  - [.env](/home/pinokew/Koha/koha-deploy/.env)
  - [.env.example](/home/pinokew/Koha/koha-deploy/.env.example)

- Перевірено:
  - `bash scripts/verify-env.sh` — OK.


### 8) Рефакторинг patch-скриптів: структурування в `scripts/patch` + декомпозиція по файлах

- Виконано гігієну patch-flow відповідно до нового рішення (one-shot на clean Koha):
  - усі конфіг-патчі винесено в `scripts/patch/`;
  - `scripts/configure-smtp.sh` перенесено/перейменовано в:
    - [patch-koha-conf-xml.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml.sh)

- `patch-koha-templates.sh` декомпозовано на скрипти, де назва відповідає файлу, який патчиться:
  - [patch-koha-common-cnf.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-common-cnf.sh)
  - [patch-koha-sites-conf.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sites-conf.sh)
  - [patch-sipconfig-xml.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-sipconfig-xml.sh)
  - [patch-koha-conf-site-xml-in.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-site-xml-in.sh)

- Додано оркестратор:
  - [patch-koha-templates.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-templates.sh)
  - запускає кроки послідовно в одному one-shot flow.

- Додано спільний helper для patch-скриптів:
  - [_patch_common.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/_patch_common.sh)
  - уніфікує завантаження `.env`, валідацію шляхів і базовий mapping env-змінних.

- Додатково:
  - виправлено старий дефект із пошуком `.env` для скриптів у вкладеній директорії;
  - для `patch-koha-conf-site-xml-in.sh` ключі-шаблони зроблено детермінованими (idempotent rerun) через стабільний derivation key.

- Перевірено:
  - `bash -n` на нових patch-скриптах — OK;
  - `bash scripts/verify-env.sh` — OK.


### 9) Додано `bootstrap-live-configs.sh` + видалено непотрібні template-path змінні

- Реалізовано one-shot bootstrap для live конфігів у volume:
  - [bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)

- Скрипт:
  - чекає появи `koha-conf.xml` у `VOL_KOHA_CONF/$KOHA_INSTANCE`;
  - робить backup (`.bak.bootstrap`) перед першим патчем;
  - ідемпотентно патчить блоки: `timezone`, `memcached_servers`, `message_broker`, `smtp_server`;
  - верифікує ключові значення;
  - за замовчуванням перезапускає `koha` (можна `--no-restart`), підтримує `--dry-run`.

- Для сумісності з паролями типу `C&...` (shell-metachar) завантаження `.env` зроблено через dotenv parser, а не `source`.
- У поточному `.env` пароль SMTP заквотовано (`SMTP_PASSWORD='...'`), щоб не ламати інші скрипти, які ще використовують `source .env`.

- Прибрано як непотрібні ключі:
  - `KOHA_OFFICIAL_TEMPLATES_DIR`
  - `KOHA_TARGET_TEMPLATES_DIR`

- Оновлено:
  - [.env](/home/pinokew/Koha/koha-deploy/.env)
  - [.env.example](/home/pinokew/Koha/koha-deploy/.env.example)

- Перевірено:
  - `bash -n scripts/bootstrap-live-configs.sh` — OK;
  - `bash scripts/bootstrap-live-configs.sh --dry-run --no-restart --wait-timeout 10` — OK;
  - `bash scripts/verify-env.sh` — OK.

### 10) Перехід на live patch modules + селектор у `bootstrap-live-configs.sh`

- Повністю переведено patch-flow на live-конфіги у volume (`koha-conf.xml`), без template-based pipeline.

- Оновлено helper:
  - [_patch_common.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/_patch_common.sh)
  - функції: dotenv-safe loader (без `source`), wait-for-file, backup bootstrap, спільні аргументи (`--env-file`, `--wait-timeout`, `--dry-run`, `--no-wait`).

- Додано live-модулі (кожен патчить `koha-conf.xml`, окремий логічний блок):
  - [patch-koha-conf-xml-timezone.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-timezone.sh)
  - [patch-koha-conf-xml-memcached.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-memcached.sh)
  - [patch-koha-conf-xml-message-broker.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-message-broker.sh)
  - [patch-koha-conf-xml-smtp.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-smtp.sh)
  - [patch-koha-conf-xml-verify.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml-verify.sh)

- Оновлено оркестратор:
  - [bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - підтримує:
    - `--all` (або default),
    - `--modules smtp,verify`,
    - `--module <name>` (repeatable),
    - `--list-modules`.
  - при `--dry-run` verify-крок пропускається, якщо в запуску є patch-модулі.

- Backward compatibility wrappers:
  - [patch-koha-conf-xml.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-conf-xml.sh) -> викликає bootstrap з модулями `timezone,memcached,message-broker,smtp,verify`.
  - [patch-koha-templates.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-templates.sh) -> deprecated wrapper на live-bootstrap.

- Прибрано template-only модулі з `scripts/patch`, які покладались на `KOHA_OFFICIAL_TEMPLATES_DIR/KOHA_TARGET_TEMPLATES_DIR`.

- Перевірено:
  - `bash -n` для bootstrap + patch modules — OK;
  - `bootstrap --list-modules` — OK;
  - dry-run сценарії: `--all`, `--modules smtp,verify`, `--module smtp` — OK;
  - `bash scripts/verify-env.sh` — OK.

### 11) Фікс integrity-check у `backup.sh` (`SHA256SUMS.*` self-include)

- Виправлено дефект у [backup.sh](/home/pinokew/Koha/koha-deploy/scripts/backup.sh) (крок `[7/7] Verify artifacts, checksums, metadata`):
  - тимчасовий файл `SHA256SUMS.XXXXXX` потрапляв у `find` і додавався у власний список checksum;
  - після `mv` цього tmp-файлу в `SHA256SUMS` перевірка `sha256sum -c` падала з `No such file or directory`.

- Зміни:
  - tmp checksum-файл тепер створюється поза `WORK_DIR` (`mktemp` без шаблону в поточній директорії);
  - додано явне виключення `! -name 'SHA256SUMS.*'` під час формування списку.

- Результат:
  - integrity-check більше не включає службовий tmp-файл у checksum-маніфест;
  - помилка `sha256sum: ./SHA256SUMS.<suffix>: No such file or directory` усунена.

### 12) Практична перевірка: backup + `bootstrap-live-configs.sh --all`

- Після фіксу виконано реальний backup:
  - `./scripts/backup.sh`
  - backup завершився успішно, checksum-крок `[7/7]` пройдено без помилок;
  - артефакти створено в `/var/backups/koha/2026-03-02_20-02-30`.

- Виконано реальний запуск оркестратора live patch modules:
  - `bash scripts/bootstrap-live-configs.sh --all --wait-timeout 60`
  - модулі `timezone`, `memcached`, `message-broker`, `smtp`, `verify` — OK;
  - створено bootstrap-backup `koha-conf.xml.bak.bootstrap`;
  - `verify` підтвердив відповідність `koha-conf.xml` до `.env`;
  - `koha` перезапущено після патчу.

- Перевірено:
  - `docker compose ps` — сервіси стеку `Up`, критичні `db/es/rabbitmq/koha` у `healthy`;
  - data-check не виконувався (конфігураційні зміни + backup/ops).

### 13) SMTP runtime test (MS365): конфіг застосований, але auth-залежність відсутня в образі

- Виконано:
  - `bash scripts/test-smtp.sh`

- Результат:
  - тест не пройшов, помилка:
    - `SMTP auth requires MIME::Base64 and Authen::SASL`
  - додаткова діагностика в контейнері `koha`:
    - `MIME::Base64` — присутній;
    - `Authen::SASL` — відсутній (`Can't locate Authen/SASL.pm`).

- Висновок:
  - `koha-conf.xml` SMTP-конфіг застосовано коректно, але для MS365 (SMTP AUTH) поточний `KOHA_IMAGE` не містить потрібної Perl-залежності `Authen::SASL`;
  - без цієї залежності runtime-відправка через authenticated SMTP не працюватиме.

### 14) Перехід на image-level fixed startup (без локального override у deploy-репо)

- Після оновлення build-репо образу Koha:
  - `scripts/koha-setup/steps/06-koha-create.sh` зроблено idempotent (early-exit, якщо `${KOHA_CONF}` вже існує і непорожній);
  - у `Dockerfile` прибрано snakeoil SSL артефакти для закриття Trivy `secret` finding:
    - `/etc/ssl/private/ssl-cert-snakeoil.key`
    - `/etc/ssl/certs/ssl-cert-snakeoil.pem`

- У deploy-репо прибрано тимчасовий workaround, який більше не потрібен:
  - видалено локальний override файл:
    - `files/overrides/06-koha-create.sh`
  - прибрано mount override з compose:
    - [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml)

- Статус перевірки:
  - за запитом користувача додаткові технічні перевірки в цьому кроці не запускались;
  - результат runtime-перевірки підтверджено користувачем вручну: конфіг більше не перезаписується.

### 15) SMTP підтверджено + додано `cd-deploy` у CI/CD workflow

- SMTP:
  - runtime тест успішний:
    - `bash ./scripts/test-smtp.sh`
    - результат: `SMTP send OK`, `SMTP test passed`.
  - висновок: SMTP конфіг у Koha робочий на поточній конфігурації M365.

- CI/CD:
  - оновлено workflow:
    - [.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)
  - додано job `cd-deploy` (за аналогією з DSpace підходом):
    - запускається тільки для `push` у `main` (owner `pinokew`);
    - залежить від успішних `ci-checks` + `build-and-publish`;
    - деплой через SSH на основний сервер, `docker compose pull` + `up -d --remove-orphans`;
    - викликає `scripts/bootstrap-live-configs.sh` після підйому сервісів;
    - має health-check цільового сервісу `koha` з retry/timeout.
  - параметри деплою та підстановки винесено в top-level `env`:
    - `DEPLOY_PROJECT_DIR`, `DEPLOY_BRANCH`, `DEPLOY_COMPOSE_FILE`, `DEPLOY_SERVICES`,
    - `DEPLOY_ENV_VERIFY_SCRIPT`, `DEPLOY_BOOTSTRAP_*`, `DEPLOY_HEALTH_*`.
  - виправлено умовний запуск Tailscale step через `env.TAILSCALE_AUTHKEY`.

- Перевірено:
  - workflow пройшов лінт:
  - `actionlint .github/workflows/ci-cd-checks.yml` (через контейнер `rhysd/actionlint:1.7.8`) — OK.

### 16) CD fix: `pull access denied` для локальних образів `koha-local-*`

- Проблема на `cd-deploy`:
  - `docker compose pull` намагався тягнути `koha-local-rabbitmq`, `koha-local-es`, `koha-local-memcached`;
  - ці образи мають збиратися з локального `build` context, а не завантажуватись з реєстру.

- Виправлено у workflow:
  - [.github/workflows/ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)
  - додано розділення сервісів для деплою:
    - `DEPLOY_PULL_SERVICES`: `db koha tunnel`
    - `DEPLOY_BUILD_SERVICES`: `rabbitmq es memcached`
    - `DEPLOY_SERVICES`: повний список для `up -d`
  - у SSH deploy script:
    - `docker compose pull` виконується тільки для `DEPLOY_PULL_SERVICES`;
    - `docker compose build` виконується для `DEPLOY_BUILD_SERVICES`;
    - після цього стандартний `docker compose up -d --remove-orphans`.

- Додатково:
  - прибрано YAML alias для checkout step (actionlint-несумісність), checkout кроки зроблено явними в кожному job.

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` (через контейнер `rhysd/actionlint:1.7.8`) — OK.
