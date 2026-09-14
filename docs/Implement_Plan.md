# Усунення росту MariaDB через Koha sessions

## Резюме

- Перевести `SessionStorage` з `mysql` на `memcached`.
- Замінити session-generating healthcheck: нинішній `HEAD /` кожні 10 секунд створює приблизно 8 640 сесій на добу.
- Після smoke-test одноразово очистити старі MySQL-сесії штатним `cleanup_database.pl`.
- Не змінювати `backup.sh`, формат backup set, PITR або 7-денний binlog retention.
- Не створювати постійний cleanup timer: після міграції таблиця `sessions` більше не повинна поповнюватися.

## Реалізація

- Додати `KOHA_SESSION_STORAGE=memcached` до env-контракту та bootstrap-модуль `session-storage`.
- Перед перемиканням модуль виконує реальний Memcached set/get/delete probe, застосовує `SessionStorage` через штатний `C4::Context->set_preference` і перевіряє результат.
- Додати fail-closed startup preflight: коли вибрано Memcached, Koha web чекає його доступності до запуску Plack і не переходить мовчки на file sessions.
- Додати Memcached healthcheck; залишити поточний cache limit 64 MB, бо зараз використано лише 154 KB і eviction відсутні.
- Замінити Koha healthcheck на `GET /api/v1/public/libraries?_per_page=1`: endpoint перевіряє Apache, Plack і DB, але не проходить через login/session flow. Декларативно забезпечити `RESTPublicAPI=1`.
- Прибрати глобальні `Koha::Caches->flush_all` із syspref deploy-потоків. Оновлювати лише потрібні syspref cache keys через штатний API, щоб звичайний deploy не видаляв Memcached sessions.
- Додати guarded `scripts/cleanup-koha-sessions.sh`: default dry-run, destructive запуск лише з `--confirm`; перед очищенням обов’язково перевіряє `SessionStorage=memcached` і Memcached roundtrip, потім виконує штатний `cleanup_database.pl --sessions --confirm --verbose` та вимагає `sessions=0`.
- У `restore.sh` після відновлення БД, застосування `SessionStorage=memcached` і успішної перевірки автоматично очищати відновлені stale sessions. Dry-run нічого не видаляє.
- Оновити архітектуру, DR/runbook та активний changelog. Офіційний Koha manual підтверджує призначення `SessionStorage`, `timeout` і штатний `cleanup_database.pl --sessdays`; встановлений код Koha 25.05.14 додатково підтверджує backend `memcached` і поведінку `--sessions`. [Koha SessionStorage/Timeout](https://koha-community.org/manual/25.05/de/html/administrationpreferences.html), [Koha cleanup_database](https://koha-community.org/manual/21.11/it/html/cron_jobs.html)

## Інтерфейси

- Env: `KOHA_SESSION_STORAGE=memcached`; дозволені значення `memcached` і `mysql`.
- CLI: `scripts/cleanup-koha-sessions.sh --env prod --dry-run|--confirm`.
- Backup-артефакти, їхній склад та PITR-контракт залишаються без змін.

## Перевірка і rollout

- Regression tests: порядок bootstrap, Memcached fail-closed preflight, idempotent syspref update, відсутність глобального cache flush, cleanup guards і session-free healthcheck.
- Запустити `bash -n`, ShellCheck, усі `tests/*.sh`, Compose/Swarm rendering, `verify-env.sh` і `git diff --check`.
- Production rollout виконувати лише після окремого підтвердження:
  1. Зафіксувати `sessions` count/size, binlog position і Memcached stats.
  2. Розгорнути зміни; перевірити `SessionStorage=memcached`.
  3. Виконати login smoke-test і підтвердити збереження сесії після restart лише Koha web.
  4. Провести щонайменше 12 healthchecks і підтвердити, що `sessions` count не збільшився.
  5. Перевірити `curr_items`, `bytes`, `evictions=0`.
  6. Запустити guarded cleanup з `--confirm`; перевірити `COUNT(*)=0`.
  7. Переконатися, що нові binlog-події не містять змін `sessions`.
  8. Перевірити наступний SQL backup: він має зменшитися одразу. Binlog-архів спочатку стабілізується, а старі великі файли зникнуть після 7-денного expiry та штатної rotation; вручну `PURGE BINARY LOGS` не виконувати.

## Прийняті припущення

- Допустимий одноразовий logout під час міграції та logout після restart/eviction Memcached.
- Звичайний restart Koha web не повинен завершувати сесії.
- Постійний MySQL cleanup timer не потрібен; варіант `--sessdays` відхилено як симптоматичний і дорогий для мільйонів BLOB-рядків.
- Memcached залишається тільки у внутрішній `kohanet`, без опублікованих портів.
