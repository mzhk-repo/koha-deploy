# CHANGELOG 2026 VOL 10

Продовження після досягнення `VOL_09` soft limit. Активний том для fail-safe змін deploy/runtime.

### 1) Koha schema safety: destructive automatic import заборонено на deploy-рівні

- Контекст (2026-09-07):
  - image-level `07-db-import.sh` трактував будь-яку помилку SQL probe як порожню БД і запускав
    `kohastructure.sql`, який містить destructive `DROP TABLE IF EXISTS`;
  - у Swarm `depends_on` не гарантує порядок старту, тому тимчасова недоступність DNS/DB під час reboot
    могла помилково активувати import для вже встановленої БД.

- Зміни:
  - `docker-compose.yml` і `docker-compose.swarm.yml` завжди додають `07-db-import.sh` до
    `KOHA_SETUP_SKIP_STEPS`, незалежно від значення з env; Swarm entrypoint повторно примусово додає skip
    після завантаження `app_env_payload`, тому runtime secret не може його скасувати; це захищає також
    старі опубліковані образи;
  - додано `scripts/koha-db-schema-guard.sh`: перед post-deploy patches він fail-closed перевіряє
    наявність непорожнього `systempreferences.Version` через фактичний Koha DB connection;
  - guard запускається перед `bootstrap-live-configs.sh`, тому помилка з'єднання, відсутня таблиця,
    порожній або відсутній `Version` не допускають syspref UPSERT;
  - `.env.example` і `docs/ARCHITECTURE.md` фіксують новий контракт: порожня БД ініціалізується тільки
    через Koha Web installer або штатний restore, після чого deploy запускається повторно;
  - додано regression test `tests/koha-db-import-safety.test.sh` для примусового skip і порядку guard.

- Перевірено:
  - `bash -n`, ShellCheck, regression tests, Compose/Swarm manifest rendering та `git diff --check`.

### 2) Swarm deploy: додано pre-pull образу Koha перед оновленням сервісів

- Контекст (2026-09-07):
  - при оновленні digest `KOHA_IMAGE` на новий образ Docker Swarm завантажував важкі шари (~2.6 GB)
    у фазі `Preparing` уже під час оновлення сервісу;
  - `wait_for_swarm_container` очікував запущеного контейнера з таймаутом 300s і завершувався з помилкою,
    якщо pull та extraction тривали довше за таймаут.

- Зміни:
  - у `scripts/deploy-orchestrator-swarm.sh` додано функцію `runtime_env_get_value` та процедуру `pre_pull_koha_image`:
    перед запуском `docker stack deploy` у режимах `swarm` та `swarm-workers` оркестратор перевіряє наявність
    `KOHA_IMAGE` локально (`docker image inspect`) і за потреби стягує його (`docker pull`) до початку оновлення сервісів;
  - додано регресійний тест `tests/deploy-orchestrator-pre-pull.test.sh`.

- Перевірено:
  - `bash -n scripts/deploy-orchestrator-swarm.sh`;
  - `shellcheck --severity=warning scripts/deploy-orchestrator-swarm.sh`;
  - пройдено всі тести у `tests/*.sh`, включно з `tests/deploy-orchestrator-pre-pull.test.sh`;
  - `git diff --check`.

### 3) Koha sessions → Memcached: зафіксовано readonly baseline Ітерації 0

- Зафіксовано baseline у `docs/RUNBOOK_DR.md` перед будь-яким перемиканням
  backend сесій або очищенням таблиці:
  - `sessions`: `2,033,162` рядків і `data_length=475,004,928` bytes;
  - binlog position `mysql-bin.000009:2224172`, `ROW`, retention 7 днів;
  - raw binlog-файли за 2026-09-07—2026-09-12: `1,203,022,994` bytes;
  - Memcached: `curr_items=61`, `bytes=11,420`, `evictions=0`.
- Runtime deploy, restore, `TRUNCATE` і зміна grants не виконувалися.

### 4) Koha sessions → Memcached: додано bootstrap і fail-closed preflight

- Додано `KOHA_SESSION_STORAGE` до env-контракту (`mysql` за замовчуванням,
  `memcached` для rollout).
- Додано bootstrap-модуль `session-storage`, який для Memcached виконує
  set/get/delete roundtrip через `Koha::Caches`, ідемпотентно встановлює
  `SessionStorage` та перевіряє результат.
- Koha web у Compose/Swarm очікує доступний Memcached до `/init`, якщо вибрано
  `KOHA_SESSION_STORAGE=memcached`; таймаут preflight завершує старт з помилкою.
- Додано TCP healthcheck для Memcached і regression test
  `tests/koha-session-storage.test.sh`.
- Перевірено: `bash -n`, ShellCheck, усі `tests/*.sh`, env validation,
  Compose rendering і `git diff --check`. Runtime rollout не виконувався.

### 5) Koha sessions → Memcached: виправлено quoting bootstrap probe

- Після першого dev rollout `session-storage` падав із `sh: 1: Syntax error:
  "(" unexpected` під час передачі Perl probe через `koha-shell -c`.
- Probe і `SessionStorage` verification переведено на сумісний із `koha-shell`
  command quoting без вкладених shell-аргументів.
- Перевірено реальний set/get/delete probe у запущеному dev Koha-контейнері:
  `Memcached session probe ok`.

### 6) Koha sessions: healthcheck переведено на session-free public REST endpoint

- Koha healthcheck замінено з `HEAD /` на GET
  `/api/v1/public/libraries?_per_page=1`.
- `api-prefs` bootstrap тепер гарантує `RESTPublicAPI=1`, необхідний для
  доступу endpoint без login/session flow.
- Додано regression-перевірку endpoint і видалення старого `--spider`
  healthcheck-патерна.

### 7) Koha sessions: одноразове очищення після переходу на Memcached

- Після preflight `SessionStorage=memcached` і успішного Memcached roundtrip
  виконано `TRUNCATE TABLE sessions` у dev mirror.
- Результат: `sessions` зменшено з `2,033,351` до `0` рядків.
- Binlog підтверджує одну коротку Query-подію `TRUNCATE TABLE sessions`
  (`mysql-bin.000010:71744` → `71884`), без масиву DELETE-подій.
- Memcached залишився доступним, `evictions=0`; окремий cleanup timer не
  додавався.

### 8) MariaDB binlog purge та повний backup без PITR

- Контекст (2026-09-23):
  - на MariaDB 11.8 `slave_connections_needed_for_purge=1` за відсутності підключених реплік
    блокував автоматичне очищення старих binlog попри `DB_BINLOG_EXPIRE_DAYS=7`;
  - backup архівував усі наявні binlog, хоча PITR для цього стеку не використовується.

- Зміни:
  - у MariaDB Compose command встановлено `--slave-connections-needed-for-purge=0`;
  - з `backup.sh` вилучено PITR metadata та архівацію binlog; SQL dump, архіви томів,
    контрольні суми, retention та offsite copy збережено;
  - з `restore.sh` вилучено `--pitr-datetime` і відтворення binlog; старі повні backup set
    залишаються придатними для SQL restore;
  - оновлено env template, валідацію env та операційну документацію. RPO тепер
    обмежене частотою повних backup.

- Перевірено: `bash -n`, ShellCheck, Compose/Swarm rendering, `git diff --check`.
  Runtime deploy, purge binlog і restore не виконувалися.
