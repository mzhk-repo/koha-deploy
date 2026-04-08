# Runbook: `scripts/deploy-orchestrator.sh` та `scripts/patch/*`

## 1) Призначення
Цей runbook описує роботу двох груп скриптів:

- `scripts/deploy-orchestrator.sh` — pre-deploy оркестратор підготовчих кроків.
- `scripts/patch/*` + `scripts/bootstrap-live-configs.sh` — live-патчі конфігурації Koha (XML, DB sysprefs, CSP-файл) після підняття стеку.

Документ орієнтований на операційне використання: перший запуск, повторні зміни, dry-run, відкат, troubleshooting.

---

## 2) Важлива межа відповідальності

### `deploy-orchestrator.sh` **НЕ** виконує `docker compose up`
Скрипт:
1. запускає `scripts/verify-env.sh` (якщо executable),
2. запускає `scripts/init-volumes.sh` (якщо executable),
3. лише повідомляє, що `bootstrap-live-configs.sh` треба запускати окремо.

Тобто рекомендований high-level flow:
1. `bash scripts/deploy-orchestrator.sh`
2. `docker compose up -d`
3. `bash scripts/bootstrap-live-configs.sh --all`

---

## 3) Передумови

- Запуск з кореня репозиторію.
- Валідний `.env` (або кастомний `--env-file`).
- Працюючий Docker daemon.
- Для DB-патчів: контейнери `db` і `koha` мають бути запущені.
- Для XML-патчів: має існувати `koha-conf.xml` у `VOL_KOHA_CONF/<KOHA_INSTANCE>/koha-conf.xml`.

Ключові env-змінні, що часто потрібні:
- `DB_ROOT_PASS`, `DB_NAME`
- `VOL_KOHA_CONF`, `KOHA_INSTANCE`

---

## 4) Швидкий старт (production-safe)

```bash
# 1) Переддеплой перевірки/підготовка
bash scripts/deploy-orchestrator.sh

# 2) Підняти стек
docker compose up -d

# 3) Перевірити, що koha/db up
docker compose ps

# 4) Прогнати всі live-патчі
bash scripts/bootstrap-live-configs.sh --all
```

Без перезапуску `koha` (коли треба керований restart-window):
```bash
bash scripts/bootstrap-live-configs.sh --all --no-restart
```

Dry-run:
```bash
bash scripts/bootstrap-live-configs.sh --all --dry-run
```

---

## 5) `deploy-orchestrator.sh`: деталі

Файл: `scripts/deploy-orchestrator.sh`

Що робить:
- Логує кроки з префіксом `[deploy-orchestrator]`.
- Виконує:
  - `scripts/verify-env.sh`
  - `scripts/init-volumes.sh`
- Не запускає deploy контейнерів.

Типове застосування:
```bash
bash scripts/deploy-orchestrator.sh
```

Коли падає:
- невалідний `.env` / розсинхрон `.env` vs `.env.example`
- відсутні права на створення/власність volume-директорій

---

## 6) `bootstrap-live-configs.sh`: оркестратор модулів

Файл: `scripts/bootstrap-live-configs.sh`

### Опції
- `--all` — всі модулі (дефолт, якщо нічого не вказано)
- `--modules a,b,c` — список через кому
- `--module name` — повторювана опція
- `--list-modules`
- `--env-file FILE`
- `--wait-timeout SEC`
- `--dry-run`
- `--no-restart`

### Порядок модулів
`timezone trusted-proxies memcached message-broker smtp domain-prefs identity-provider oidc-prefs opac-matomo csp-report-only verify`

### Логіка restart
- Якщо виконувався хоча б один patch-модуль (окрім `verify`), у кінці робиться:
  ```bash
  docker compose -f docker-compose.yaml --env-file <env> up -d koha
  ```
- `--no-restart` вимикає цей крок.
- `--dry-run` завжди пропускає restart.

### Поведінка `verify` у dry-run
Якщо у `--dry-run` обрані patch-модулі, `verify` буде пропущено автоматично (щоб не звіряти незмінений файл).

---

## 7) Загальні механіки `scripts/patch/*`

Базовий helper: `scripts/patch/_patch_common.sh`

Що дає:
- Парсинг common-опцій: `--env-file`, `--wait-timeout`, `--dry-run`, `--no-wait`
- Надійний парсер dotenv (без `source .env`)
- Очікування появи live-файлу `koha-conf.xml`
- Автобекап: `koha-conf.xml.bak.bootstrap` (створюється один раз, не в dry-run)

Загальний шаблон XML-модулів:
1. `prepare_live_context`
2. patch через `perl -0777 -i -pe`
3. локальна верифікація через `grep`/`sed`

---

## 8) Каталог модулів `scripts/patch/*`

### 8.1 XML-модулі (працюють із live `koha-conf.xml`)

1. `patch-koha-conf-xml-timezone.sh`
- Модуль bootstrap: `timezone`
- Що міняє: `<timezone>`
- Env: `KOHA_TIMEZONE` (default `Europe/Kyiv`)

2. `patch-koha-conf-xml-trusted-proxies.sh`
- Модуль bootstrap: `trusted-proxies`
- Що міняє: `<koha_trusted_proxies>` (replace або insert)
- Env: `KOHA_TRUSTED_PROXIES`

3. `patch-koha-conf-xml-memcached.sh`
- Модуль bootstrap: `memcached`
- Що міняє: `<memcached_servers>`
- Env: `MEMCACHED_SERVERS` (default `memcached:11211`)

4. `patch-koha-conf-xml-message-broker.sh`
- Модуль bootstrap: `message-broker`
- Що міняє: блок `<message_broker>`
- Env: `MB_HOST`, `MB_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASS`

5. `patch-koha-conf-xml-smtp.sh`
- Модуль bootstrap: `smtp`
- Що міняє: блок `<smtp_server>`
- Env: `SMTP_HOST`, `SMTP_PORT`, `SMTP_TIMEOUT`, `SMTP_SSL_MODE`, `SMTP_USER_NAME`, `SMTP_PASSWORD`, `SMTP_DEBUG`

6. `patch-koha-conf-xml-verify.sh`
- Модуль bootstrap: `verify`
- Read-only звірка XML проти `.env`

### 8.2 DB-модулі (працюють через `docker compose exec db mariadb`)

7. `patch-koha-sysprefs-domain.sh`
- Модуль bootstrap: `domain-prefs`
- Що міняє: `systempreferences` (`OPACBaseURL`, `staffClientBaseURL`)
- Env: `OPACBaseURL` і `staffClientBaseURL` (пріоритетно), або fallback `KOHA_OPAC_SERVERNAME`, `KOHA_INTRANET_SERVERNAME`, плюс `DB_ROOT_PASS`, `DB_NAME`

8. `patch-koha-identity-provider.sh`
- Модуль bootstrap: `identity-provider`
- Що міняє: `identity_providers`, `identity_provider_domains`, частково Google OIDC sysprefs
- Env: `KOHA_IDP_*` + `DB_ROOT_PASS`, `DB_NAME`
- Важливо:
  - За замовчуванням виконує `discover + apply + verify`
  - Якщо передати хоча б один із `--discover|--apply|--verify`, виконуються тільки явно обрані
  - Для `default_library_id/default_category_id` робить FK-перевірку; невалідні значення переводить у `NULL` з warning

9. `patch-koha-sysprefs-oidc.sh`
- Модуль bootstrap: `oidc-prefs`
- Що міняє: довільні OIDC-пов’язані sysprefs із env-ключів `KOHA_OIDC_PREF__*`
- Env: `KOHA_OIDC_PREF__<SystemPreference>=<value>` (+ `KOHA_OIDC_INCLUDE_EMPTY=true` за потреби)

10. `patch-koha-sysprefs-opac-matomo.sh`
- Модуль bootstrap: `opac-matomo`
- Що міняє: JS syspref (default `OPACUserJS`) контентом з шаблона Matomo
- Env: `MATOMO_*`, `KOHA_OPAC_JS_PREF_KEY`, `MATOMO_SNIPPET_FILE`, плюс DB creds

### 8.3 File-модуль (Apache)

11. `patch-koha-apache-csp-report-only.sh`
- Модуль bootstrap: `csp-report-only`
- Що генерує: `apache/csp-report-only.conf`
- Env: `CSP_REPORT_ONLY_ENABLED`, `CSP_MODE`, `CSP_REPORT_ONLY_*`
- Якщо `CSP_REPORT_ONLY_ENABLED=false` — файл видаляється

### 8.4 Wrapper-скрипти

- `patch-koha-conf-xml.sh`
  - Convenience wrapper на bootstrap із модулями:
    `timezone,memcached,message-broker,smtp,verify`

- `patch-koha-templates.sh`
  - Deprecated wrapper, просто запускає `bootstrap-live-configs.sh --all`

---

## 9) Практичні сценарії

### Сценарій A: Повний пост-деплой patch
```bash
bash scripts/bootstrap-live-configs.sh --all
```

### Сценарій B: Лише SMTP + verify
```bash
bash scripts/bootstrap-live-configs.sh --modules smtp,verify
```

### Сценарій C: Точковий OIDC apply без discover (менше чутливого в логах)
```bash
bash scripts/patch/patch-koha-sysprefs-oidc.sh --apply --verify
```

### Сценарій D: Identity Provider без discover
```bash
bash scripts/patch/patch-koha-identity-provider.sh --apply --verify
```

### Сценарій E: Перевірити модулі без змін
```bash
bash scripts/bootstrap-live-configs.sh --all --dry-run
```

---

## 10) Безпека і секрети

1. `discover` у `patch-koha-identity-provider.sh` показує поточні DB-дані провайдера (можуть містити секрети).
2. Логи CI/CD для patch-скриптів треба вважати чутливими.
3. Для безпечніших прогонів у CI використовуйте вибіркові флаги `--apply --verify` без `--discover`.

---

## 11) Idempotency та rollback

### Idempotency
- Більшість модулів повторно застосовні (повторний запуск приводить до того ж цільового стану).
- `bootstrap-live-configs.sh --all` можна запускати повторно після змін у `.env`.

### Rollback
1. XML rollback:
```bash
cp -a "${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml.bak.bootstrap" \
      "${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml"
```
2. DB rollback:
- з SQL backup/restore (`scripts/backup.sh` / `scripts/restore.sh`) або вашим стандартним процесом.
3. Після rollback:
```bash
docker compose up -d koha
```

---

## 12) Troubleshooting

1. `koha-conf.xml not found in volume within timeout`
- Перевірте `VOL_KOHA_CONF`, `KOHA_INSTANCE`, стан контейнера `koha`
- Збільшіть `--wait-timeout`

2. `Unknown option` / `Unknown module`
- Перевірте `--list-modules`

3. `docker compose exec db ... Access denied`
- Перевірте `DB_ROOT_PASS`, `DB_NAME` у обраному `--env-file`

4. FK-помилка в `identity_provider_domains`
- Невалідні `KOHA_IDP_DEFAULT_LIBRARY_ID` / `KOHA_IDP_DEFAULT_CATEGORY_ID`
- Поточна логіка ставить `NULL` і дає warning; за потреби задайте валідні коди

5. `No KOHA_OIDC_PREF__* mappings found`
- Додайте `KOHA_OIDC_PREF__...` у `.env` або пропустіть модуль `oidc-prefs`

6. Після patch зміни “не видно”
- Перевірте, чи був restart `koha` (або ви запускали з `--no-restart`)

7. Права на volume-директорії
- Прогнати:
```bash
bash scripts/init-volumes.sh --fix-existing
```

---

## 13) Обмеження та примітки щодо Swarm

- Patch-скрипти жорстко використовують `docker compose -f docker-compose.yaml ...`, а не `docker stack`.
- Для Swarm-процесів ці скрипти можна використовувати лише якщо на вузлі доступний той самий compose-проєкт/DB-контейнер під очікуваними іменами.

---

## 14) Рекомендований операційний чекліст

1. `bash scripts/deploy-orchestrator.sh`
2. `docker compose up -d`
3. `docker compose ps` (db/koha healthy)
4. `bash scripts/bootstrap-live-configs.sh --all`
5. `docker compose logs --tail=200 koha`
6. Smoke-test OPAC/staff URL
