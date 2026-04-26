

## 2026-03-13

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

### 18) CSP enforcement smoke-check: виявлено runtime регресії, повернення в safe-режим (report-only у SSOT)

- Контекст:
  - після переходу в enforcement під час browser smoke-check зафіксовано блокування `unsafe-eval` (Gettext/i18n) і Cloudflare beacon script;
  - Matomo (`matomo.js` + `js/ping`) продовжував працювати.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - [/home/pinokew/Koha/koha-deploy/apache/csp-report-only.conf](/home/pinokew/Koha/koha-deploy/apache/csp-report-only.conf)

- Зміни:
  - для сумісності додано до `CSP_REPORT_ONLY_SCRIPT_SRC`:
    - `'unsafe-eval'`
    - `https://static.cloudflareinsights.com`
  - `CSP_MODE` повернуто в `report-only` у `.env`/`.env.example` (safe rollback для стабілізації UX, поки завершуємо tuning).

- Перевірено (services/network/data):
  - `bash ./scripts/verify-env.sh` — OK;
  - `bash ./scripts/bootstrap-live-configs.sh --modules csp-report-only` — OK;
  - у контейнері `koha` згенерований `zz-koha-csp-report-only.conf` містить `Content-Security-Policy-Report-Only` з `unsafe-eval` та `static.cloudflareinsights.com`;
  - origin header на `127.0.0.1:8081` все ще містить enforced `Content-Security-Policy` без нових allowlist (ймовірно, окреме джерело/override поза керованим шаблоном).

- Висновок:
  - для production-safe переходу до enforcement потрібно окремо ідентифікувати джерело enforced CSP у runtime (не збігається з керованим файлом `zz-koha-csp-report-only.conf`) і лише потім фіналізувати CSP 2.4.

### 19) OIDC UI налаштування винесено в IaC: новий оркестрований модуль `oidc-prefs`

- Контекст:
  - OIDC параметри були налаштовані вручну через Koha UI;
  - для узгодження з SSOT/IaC додано керування через deploy-репозиторій та env.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-oidc.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-oidc.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - [/home/pinokew/Koha/koha-deploy/README.md](/home/pinokew/Koha/koha-deploy/README.md)
  - [/home/pinokew/Koha/koha-deploy/docs/snippets/ARCHITECTURE.md](/home/pinokew/Koha/koha-deploy/docs/snippets/ARCHITECTURE.md)

- Зміни:
  - додано bootstrap-модуль `oidc-prefs` в `bootstrap-live-configs.sh`;
  - додано окремий скрипт `patch-koha-sysprefs-oidc.sh` з режимами:
    - `--discover`: показує поточні OIDC-like sysprefs (`oidc|openid|oauth|sso`);
    - `--apply`: застосовує env-мапінг `KOHA_OIDC_PREF__<SystemPreference>=<value>`;
    - `--verify`: звіряє DB значення з env.
  - додано env SSOT ключі для OIDC-оркестрації:
    - `KOHA_OIDC_INCLUDE_EMPTY` (запобігання випадковому wipe порожніми значеннями);
    - приклади `KOHA_OIDC_PREF__*` для типових OIDC sysprefs.

- Результат:
  - OIDC sysprefs більше не залежать від ручного UI-clickops;
  - секретні OIDC значення можуть керуватися тільки через env/secret-store та застосовуватись оркестратором.

### 20) Identity Provider (MS365) винесено в IaC + прибрано Google OIDC залежності

- Контекст:
  - Identity Provider був налаштований вручну через Koha UI;
  - потрібно перевести в SSOT/IaC і прибрати Google OIDC-спадок.

- Оновлено:
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-identity-provider.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-identity-provider.sh)
  - [/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh](/home/pinokew/Koha/koha-deploy/scripts/bootstrap-live-configs.sh)
  - [/home/pinokew/Koha/koha-deploy/.env.example](/home/pinokew/Koha/koha-deploy/.env.example)
  - [/home/pinokew/Koha/koha-deploy/.env](/home/pinokew/Koha/koha-deploy/.env)
  - [/home/pinokew/Koha/koha-deploy/README.md](/home/pinokew/Koha/koha-deploy/README.md)
  - [/home/pinokew/Koha/koha-deploy/docs/snippets/ARCHITECTURE.md](/home/pinokew/Koha/koha-deploy/docs/snippets/ARCHITECTURE.md)
  - [/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-oidc.sh](/home/pinokew/Koha/koha-deploy/scripts/patch/patch-koha-sysprefs-oidc.sh)

- Зміни:
  - додано новий bootstrap-модуль `identity-provider`, який керує таблицями `identity_providers` та `identity_provider_domains` з env;
  - зчитано поточну MS365 конфігурацію з БД і винесено всі наявні поля в `.env`:
    - провайдер: `AzureID` (`OIDC`, `matchpoint=userid`, `description=MS365`);
    - config: `key`, `secret`, `well_known_url`, `scope`;
    - mapping: `userid`, `email`, `firstname`, `surname`;
    - domain rules: `domain=*`, `update_on_auth=1`, `default_library_id=CPL`, `default_category_id=ST`, `allow_opac=1`, `allow_staff=1`, `auto_register_opac=1`, `auto_register_staff=0`.
  - додано автоматичне відключення/очищення Google OIDC sysprefs (керується `KOHA_DISABLE_GOOGLE_OIDC=true`).

- Перевірено (data/services):
  - `bash scripts/patch/patch-koha-identity-provider.sh --discover --dry-run` — OK;
  - `bash scripts/bootstrap-live-configs.sh --module identity-provider` — OK;
  - у БД підтверджено актуальні значення `identity_providers`/`identity_provider_domains` для `AzureID`;
  - Google sysprefs підтверджено у вимкненому/очищеному стані (`GoogleOpenIDConnect=0`, `GoogleOpenIDConnectAutoRegister=0`, `RESTOAuth2ClientCredentials=0`, решта очищені).

## 2026-04-24

### 21) Scripts refactoring: оновлено preflight Категорії 1а для Swarm-оркестратора

- Контекст:
  - `scripts/check-secrets-hygiene.sh` виводиться зі scope, бо перевірку секретів виконує Gitleaks у CI;
  - репозиторій використовує `docker-compose.yml`, а частина 1а-перевірок очікувала `docker-compose.yaml`.

- Оновлено:
  - `scripts/check-ports-policy.sh`
  - `scripts/check-internal-ports-policy.sh`
  - `scripts/deploy-orchestrator-swarm.sh`

- Зміни:
  - прибрано виклик `check-secrets-hygiene.sh` з `check-ports-policy.sh`;
  - додано detection `docker-compose.yaml|docker-compose.yml` для port-policy preflight;
  - у `deploy-orchestrator-swarm.sh` додано `run_validation_scripts()` перед роботою з env-файлом і deploy-кроком;
  - fallback-повідомлення для локального `.env` уточнено як dev-only сценарій.

- Перевірено:
  - `bash -n scripts/check-ports-policy.sh scripts/check-internal-ports-policy.sh scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/check-ports-policy.sh` — OK;
  - `COMPOSE_FILE=docker-compose.yml bash scripts/verify-env.sh --example-only` — OK;
  - `bash scripts/check-internal-ports-policy.sh` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK.

### 22) Scripts refactoring: єдиний безпечний env-flow для Категорії 1б

- Контекст:
  - deploy-adjacent скрипти мають отримувати env з `ORCHESTRATOR_ENV_FILE` після CI/SOPS-розшифровки;
  - для локального dev збережено fallback на `.env`;
  - `source`/eval для env-файлів у 1б заборонено.

- Оновлено:
  - `scripts/lib/orchestrator-env.sh`
  - `scripts/init-volumes.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/koha-lockdown-password-prefs.sh`
  - `scripts/patch/_patch_common.sh`
  - `scripts/patch/patch-koha-sysprefs-domain.sh`
  - `scripts/patch/patch-koha-sysprefs-oidc.sh`
  - `scripts/patch/patch-koha-sysprefs-opac-matomo.sh`
  - `scripts/patch/patch-koha-identity-provider.sh`
  - `scripts/deploy-orchestrator-swarm.sh`

- Зміни:
  - додано спільний helper `orchestrator-env.sh`, який резолвить `--env-file` / `ORCHESTRATOR_ENV_FILE` / dev fallback `.env`;
  - env-файли читаються без `source`/eval, через безпечний dotenv-parser;
  - `init-volumes.sh`, `bootstrap-live-configs.sh`, `koha-lockdown-password-prefs.sh` приймають `--env-file`;
  - patch-модулі отримали спільний compose-file detection через `KOHA_COMPOSE_FILE`;
  - у Swarm-оркестратор підключено pre-deploy `init-volumes.sh` з `--env-file "${ENV_FILE}"`.

- Примітка:
  - `bootstrap-live-configs.sh` і `koha-lockdown-password-prefs.sh` env-сумісні з оркестратором, але не запускаються автоматично зі Swarm path на цьому кроці, бо частина модулів ще використовує `docker compose exec` і потребує окремого Swarm-native адаптера.

- Перевірено:
  - `bash -n` для змінених 1б shell-скриптів — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/patch/patch-koha-apache-csp-report-only.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `git diff --check` — OK.

### 23) Scripts refactoring: Swarm-native runtime adapter для patch/lockdown exec-команд

- Контекст:
  - частина 1б-скриптів виконувала DB/Koha команди через `docker compose exec`;
  - для Swarm path потрібен адаптер, який виконує команди у running task container за service label.

- Оновлено:
  - `scripts/lib/docker-runtime.sh`
  - `scripts/patch/_patch_common.sh`
  - `scripts/patch/patch-koha-sysprefs-domain.sh`
  - `scripts/patch/patch-koha-sysprefs-oidc.sh`
  - `scripts/patch/patch-koha-sysprefs-opac-matomo.sh`
  - `scripts/patch/patch-koha-identity-provider.sh`
  - `scripts/koha-lockdown-password-prefs.sh`

- Зміни:
  - додано `docker_runtime_exec SERVICE ...` з режимами `compose|swarm`;
  - default runtime: `ORCHESTRATOR_MODE=swarm` -> Swarm, інакше Compose;
  - Swarm mode шукає контейнер за label `com.docker.swarm.service.name=${STACK_NAME}_${service}`;
  - якщо Swarm container не знайдено, виконується fallback на `docker compose exec`;
  - якщо контейнер знайдено, помилка команди не маскується fallback-ом.

- Перевірено:
  - `bash -n` для runtime helper, patch-модулів і lockdown-скрипта — OK;
  - `bash scripts/patch/patch-koha-apache-csp-report-only.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-domain.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-opac-matomo.sh --env-file .env.example --dry-run` — OK;
  - `bash scripts/patch/patch-koha-sysprefs-oidc.sh --env-file .env.example --apply --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - runtime mode resolver (`compose`, `swarm`, `ORCHESTRATOR_MODE=swarm`) — OK;
  - `git diff --check` — OK.

### 24) Scripts refactoring: підключено post-deploy bootstrap/lockdown у Swarm-оркестратор

- Контекст:
  - після появи `docker-runtime.sh` patch/lockdown скрипти можуть виконувати команди через Swarm task containers;
  - `deploy-orchestrator-swarm.sh` має запускати post-deploy конфігураційні кроки після `docker stack deploy`.

- Оновлено:
  - `scripts/deploy-orchestrator-swarm.sh`
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/lib/docker-runtime.sh`

- Зміни:
  - після `docker stack deploy` оркестратор чекає running containers для `${STACK_NAME}_db` і `${STACK_NAME}_koha`;
  - далі запускає `bootstrap-live-configs.sh --env-file "${ENV_FILE}"` у `ORCHESTRATOR_MODE=swarm` / `DOCKER_RUNTIME_MODE=swarm`;
  - після bootstrap/restart повторно чекає running `${STACK_NAME}_koha`;
  - потім запускає `koha-lockdown-password-prefs.sh --env-file "${ENV_FILE}"`;
  - `bootstrap-live-configs.sh` тепер рестартить `koha` через `docker_runtime_restart_service`;
  - для Swarm restart використовується `docker service update --force ${STACK_NAME}_koha`, з Compose fallback.

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh scripts/bootstrap-live-configs.sh scripts/lib/docker-runtime.sh scripts/koha-lockdown-password-prefs.sh` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - `git diff --check` — OK.

### 25) Scripts refactoring: автономний SOPS env-flow для Категорії 2

- Контекст:
  - автономні скрипти запускаються поза CI/CD і не отримують `ORCHESTRATOR_ENV_FILE`;
  - джерело середовища для cron/manual сценаріїв: CLI `--env dev|prod` або `SERVER_ENV`;
  - розшифрований env має жити у `/dev/shm`, а не в `/tmp`.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `scripts/backup.sh`
  - `scripts/restore.sh`
  - `scripts/collect-docker-logs.sh`

- Зміни:
  - додано helper `autonomous-env.sh` для `env.dev.enc` / `env.prod.enc`;
  - helper визначає середовище через перший positional `dev|prod`, `--env dev|prod`, `--env=dev|prod` або `SERVER_ENV`;
  - env розшифровується через `sops --decrypt --input-type dotenv --output-type dotenv` у `/dev/shm/env-*`, права `600`, cleanup через `trap`;
  - `backup.sh` і `restore.sh` мінімально змінені тільки навколо env-завантаження;
  - `restore.sh` і `collect-docker-logs.sh` отримали CLI `--env dev|prod`;
  - старий `source .env` прибрано з Категорії 2.

- Перевірено:
  - `bash -n scripts/lib/autonomous-env.sh scripts/backup.sh scripts/restore.sh scripts/collect-docker-logs.sh` — OK;
  - `bash scripts/restore.sh --help` — OK;
  - `bash scripts/collect-docker-logs.sh --help` — OK;
  - helper parsing/resolution для `--env prod`, `--env=dev`, positional `production`, `development`, `prod` — OK;
  - `sops` доступний як `/usr/bin/sops`;
  - decrypt-патерн узгоджено з `/opt/Dspace/DSpace-docker/scripts/lib/autonomous-env.sh` без явного `--age-key-file`;
  - `git diff --check` — OK.

### 26) Docs/scripts refactoring: синхронізовано autonomous decrypt-приклади з DSpace-патерном

- Контекст:
  - Koha helper Категорії 2 мав зайву прив'язку до `SOPS_AGE_KEY_FILE` / `${HOME}/.config/age/keys.txt`;
  - у DSpace успішний патерн використовує стандартний SOPS decrypt без явного `--age-key-file`.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `docs/scrypts_refactoring.md`
  - `docs/RUNBOOK_DR.md`
  - `docs/changelogs/CHANGELOG_2026_VOL_05.md`

- Зміни:
  - `decrypt_autonomous_env()` тепер використовує `sops --decrypt --input-type dotenv --output-type dotenv "${enc_file}"`;
  - temp-файл у `/dev/shm` приведено до DSpace-style `env-XXXXXX`;
  - roadmap/refactoring examples більше не радять `--age-key-file` або `/tmp` для тимчасового env;
  - DR runbook оновлено під `env.<env>.enc`, `SERVER_ENV=prod` і `--env prod`.

- Перевірено:
  - `bash -n scripts/lib/autonomous-env.sh` — OK;
  - `rg 'age-key|SOPS_AGE_KEY_FILE|/tmp/env' docs/scrypts_refactoring.md scripts/lib/autonomous-env.sh` — без застарілих прикладів;
  - `git diff --check` — OK.

### 27) Scripts refactoring: end-to-end non-destructive verification

- Контекст:
  - після рефакторингу Категорій 1а/1б/2 потрібна наскрізна перевірка без destructive дій.

- Перевірено:
  - `bash -n` для всіх shell-скриптів у `scripts/` — OK;
  - grep-перевірка: у 1б немає `source` / `. "$ENV_FILE"` для `ENV_FILE` або `ORCHESTRATOR_ENV_FILE` — OK;
  - grep-перевірка: прямі `docker compose exec` прибрані з patch/lockdown скриптів — OK;
  - `bash scripts/check-ports-policy.sh` — OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` — OK;
  - `bash scripts/bootstrap-live-configs.sh --env-file .env.example --module csp-report-only --dry-run` — OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` — OK;
  - `bash scripts/restore.sh --help` — OK;
  - `bash scripts/collect-docker-logs.sh --help` — OK;
  - `bash scripts/koha-lockdown-password-prefs.sh --env-file .env.example --help` — OK;
  - helper parsing/resolution для `--env prod`, `--env=dev`, positional `production`, `development`, `prod` — OK;
  - manual SOPS smoke: `sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > /dev/shm/env-*` + `ORCHESTRATOR_ENV_FILE="${ENV_TMP}" bash scripts/bootstrap-live-configs.sh --module csp-report-only --dry-run` — OK;
  - tmp env cleanup через `shred -u ... || rm -f ...` — OK.

- Примітка:
  - `backup.sh`, `restore.sh`, `collect-docker-logs.sh` не запускались у runtime-режимі, бо вони можуть взаємодіяти з Docker/backup/restore state; перевірено тільки синтаксис, help і env helper parsing.

### 28) Docs: `scripts_runbook.md` приведено до Koha-specific стану

- Контекст:
  - `docs/scripts_runbook.md` містив залишки DSpace runbook після перенесення refactoring patterns у Koha deploy repo;
  - документація має відображати фактичні Koha scripts contracts після рефакторингу Категорій 1а/1б/2.

- Оновлено:
  - `docs/scripts_runbook.md`

- Зміни:
  - прибрано DSpace-specific секції та приклади (`backup-dspace`, `restore-backup`, maintenance/user-groups/runtime start);
  - додано Koha-specific опис validation, Swarm orchestrator, `init-volumes.sh`, `bootstrap-live-configs.sh`, lockdown і patch modules;
  - додано runtime helpers `orchestrator-env.sh`, `docker-runtime.sh`, `autonomous-env.sh`;
  - описано autonomous scripts `backup.sh`, `restore.sh`, `collect-docker-logs.sh`;
  - додано non-destructive verification checklist і manual SOPS smoke через `/dev/shm/env-XXXXXX`;
  - для `install-collect-logs-timer.sh` зафіксовано потребу синхронізувати systemd unit з autonomous env contract перед production install.

- Перевірено:
  - grep-перевірка на DSpace/legacy terms у `docs/scripts_runbook.md` — без збігів;
  - `git diff --check` — OK;
  - `git diff --no-index --check /dev/null docs/scripts_runbook.md` — OK;
  - `git diff --no-index --check /dev/null docs/changelogs/CHANGELOG_2026_VOL_05.md` — OK.

### 29) Category 2 autonomous scripts switched to Swarm runtime

- Контекст:
  - автономні scripts (`backup.sh`, `restore.sh`, `collect-docker-logs.sh`) мають працювати у production Swarm runtime за тим самим контрактом, що й Matomo/DSpace;
  - попередній default для cron/manual запуску лишався compose-oriented.

- Оновлено:
  - `scripts/lib/autonomous-env.sh`
  - `scripts/lib/docker-runtime.sh`
  - `scripts/backup.sh`
  - `scripts/restore.sh`
  - `scripts/collect-docker-logs.sh`

- Зміни:
  - `autonomous-env.sh` переведено з прямого `source` decrypted dotenv на безпечний parser, щоб значення на кшталт IPv6/CIDR не виконувались як shell-код;
  - для Category 2 скриптів default runtime встановлено як `DOCKER_RUNTIME_MODE=swarm`, compose fallback лишився для local dev;
  - `backup.sh` виконує MariaDB dump/PITR metadata через `docker_runtime_exec db`; додано `--dry-run` без створення backup;
  - `restore.sh` виконує DB import, PITR, verify, service scale/reindex через runtime helper;
  - `collect-docker-logs.sh` збирає logs через `docker service logs` у Swarm mode.

- Перевірено:
  - `bash -n` і `shellcheck` для змінених Koha scripts/helper-ів — OK;
  - `backup.sh --env dev --dry-run` — OK;
  - `restore.sh --env dev --source <tmp-test-backup-set> --dry-run` — OK;
  - `collect-docker-logs.sh --env dev --since 1m --dry-run` завершився без запису state/output; Docker daemon повернув warnings для частини service logs через unavailable node/incomplete log stream.
