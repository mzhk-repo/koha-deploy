# Дорожня карта: MariaDB growth через Koha sessions → Memcached

Скоуп зафіксовано: bootstrap-модуль, fail-closed preflight збережено, healthcheck без сесій, `flush_all` без змін (деплої рідкісні), одноразовий `TRUNCATE TABLE sessions`, без нових постійних скриптів і без правок `backup.sh`/`restore.sh`.

---

## Ітерація 0 — Baseline (readonly, без деплою)

**Мета:** зафіксувати вихідний стан для порівняння після міграції.

- Зняти: `SELECT COUNT(*), MAX(data_length) FROM sessions` (наближено), розмір таблиці на диску.
- Зафіксувати поточну binlog position і розмір binlog-архіву за останні 7 днів.
- Memcached stats: `curr_items`, `bytes`, `evictions` (baseline — очікується майже порожньо).
- Перевірити грант користувача БД на `DROP` (потрібен для `TRUNCATE` в ітерації 4).

**Exit criteria:** цифри задокументовані в runbook.

---

## Ітерація 1 — Bootstrap-модуль + fail-closed preflight

**Мета:** застосунок вміє переключатись на memcached-сесії і не стартує "тихо" без нього.

- Додати `KOHA_SESSION_STORAGE=memcached` в env-контракт.
- Bootstrap-модуль: Memcached set/get/delete probe → `C4::Context->set_preference('SessionStorage', 'memcached')` → перевірка результату.
- Startup preflight: Plack не піднімається, поки Memcached-сокет не відповість (важливо саме для Swarm, де `depends_on` не гарантує порядок старту).
- Memcached healthcheck сервісу; ліміт кешу лишити 64 MB.

**Exit criteria:** локально/на staging контейнер Koha web не стартує без доступного memcached; при доступному — `SessionStorage=memcached` виставляється автоматично.

---

## Ітерація 2 — Healthcheck без генерації сесій

**Мета:** зупинити побічний ефект (сесії від healthcheck), незалежно від бекенда сесій.

- Замінити `HEAD /` на легкий endpoint без login/session flow (REST `GET /api/v1/public/libraries?_per_page=1` або простіший internal-check — обрати дешевший з двох).
- Якщо REST API — декларативно `RESTPublicAPI=1`.
- Інтервал healthcheck можна лишити 10s або підняти до 30s.

**Exit criteria:** новий healthcheck не створює запису ні в `sessions` (MariaDB), ні зайвого запису в Memcached при кожному виклику.

---

## Ітерація 3 — Тести та lint (без деплою в prod)

**Мета:** переконатися, що зміни не ламають bootstrap/deploy pipeline.

- `bash -n`, ShellCheck, усі `tests/*.sh`.
- Compose/Swarm rendering, `verify-env.sh`, `git diff --check`.
- Regression: bootstrap order, preflight fail-closed поведінка, idempotent `set_preference`, healthcheck дійсно не чіпає сесії.
- Явно підтвердити: `flush_all` у syspref deploy-потоках залишається без змін (свідоме рішення, деплої рідкісні).

**Exit criteria:** усі перевірки зелені на staging.

---

## Ітерація 4 — Production rollout (config switch)

**Мета:** перевести prod на memcached-сесії без відновлення старих даних.

1. Розгорнути зміни ітерацій 1–2.
2. Перевірити `SessionStorage=memcached` в проді.
3. Login smoke-test; підтвердити збереження сесії після restart лише Koha web.
4. Провести ≥12 healthchecks, підтвердити, що `sessions` count у MariaDB не зростає.
5. Перевірити Memcached: `curr_items`, `bytes`, `evictions=0`.

**Exit criteria:** нові сесії йдуть тільки в Memcached; MariaDB `sessions` більше не поповнюється.

---

## Ітерація 5 — Одноразове очищення (maintenance-вікно)

**Мета:** звільнити місце в MariaDB без сплеску binlog.

- Виконувати на production host у погоджене maintenance-вікно. Спочатку
  визначити поточні контейнери та пройти fail-closed preflight:

  ```bash
  set -euo pipefail
  KOHA_CID="$(docker ps -q --filter label=com.docker.swarm.service.name=koha_koha | head -n 1)"
  DB_CID="$(docker ps -q --filter label=com.docker.swarm.service.name=koha_db | head -n 1)"
  test -n "${KOHA_CID}" && test -n "${DB_CID}"

  docker exec "${KOHA_CID}" koha-mysql library -N -B -e \
    "SELECT variable, value FROM systempreferences WHERE variable='SessionStorage'; SELECT COUNT(*) FROM sessions;"

  docker exec "${KOHA_CID}" koha-shell library -c \
    'perl -MKoha::Caches -e "my \$c=Koha::Caches->get_instance; my \$k=q(iteration5_preflight); my \$v=q(ok); \$c->set_in_cache(\$k,\$v); die q(Memcached set/get failed\n) unless (\$c->get_from_cache(\$k)//q()) eq \$v; \$c->clear_from_cache(\$k); die q(Memcached delete failed\n) if defined \$c->get_from_cache(\$k); print q(Memcached roundtrip ok\n);"'

  docker exec "${DB_CID}" sh -ec \
    'mariadb -uroot -p"$(cat /run/secrets/db_root_password)" -N -B -e "SHOW MASTER STATUS;"'
  ```

- Якщо `SessionStorage` не дорівнює `memcached` або Memcached roundtrip не
  пройшов — зупинити процедуру. Не використовувати `ORCHESTRATOR_ALLOW_DB_INIT`.
- Після успішного preflight виконати через `koha-mysql`:

  ```bash
  docker exec "${KOHA_CID}" koha-mysql library -e 'TRUNCATE TABLE sessions;'
  ```

- Перевірити `COUNT(*)=0` і нову binlog position:

  ```bash
  docker exec "${KOHA_CID}" koha-mysql library -N -B -e \
    'SELECT COUNT(*) FROM sessions;'

  docker exec "${DB_CID}" sh -ec \
    'mariadb -uroot -p"$(cat /run/secrets/db_root_password)" -N -B -e "SHOW MASTER STATUS;"'

  docker exec "${DB_CID}" sh -ec \
    'mariadb -uroot -p"$(cat /run/secrets/db_root_password)" -N -B -e "SHOW BINLOG EVENTS IN \"<BINLOG_FILE_FROM_BEFORE>\" FROM <POSITION_FROM_BEFORE> LIMIT 12;"'
  ```

- Очікується одна коротка Query-подія `TRUNCATE TABLE sessions`, а не масив
  DELETE-подій. Не виконувати `PURGE BINARY LOGS`, не перезапускати Memcached
  і не запускати `TRUNCATE` повторно після успішної перевірки.

**Exit criteria:** таблиця порожня, без користувацьких скарг понад прийнятий одноразовий logout.

---

## Ітерація 6 — Пост-верифікація і документація

**Мета:** закрити задачу і зафіксувати новий steady state.

- Наступний SQL backup: перевірити, що розмір одразу зменшився.
- Binlog-архів: старі великі файли зникають природно після 7-денного expiry (без ручного `PURGE BINARY LOGS`).
- Оновити архітектуру, DR/runbook, changelog.
- Зафіксувати прийняті рішення: без постійного cleanup timer, без нових CLI-скриптів, `flush_all` збережено свідомо.

**Exit criteria:** документація відображає фактичний стан системи; задача закрита без залишкового технічного боргу.
