# CHANGELOG Volume 01 (2026)

Анотація:
- Контекст: старт production hardening, відновлення після інцидентів, впровадження roadmap 1.1 і поетапний 1.2.
- Зміст: backup/restore/PITR стабілізація, security baseline, runtime hardening (частинами), верифікація health після кожного кроку.

---

# CHANGELOG

## 2026-02-28

### 1) Оновлення образів і compose (production runtime)

- Оновлено `KOHA_IMAGE` на новий digest з фіксом `MEMCACHED_SERVERS`:
  - `pinokew/koha@sha256:ca281dc3eabcb371ebb067e3e4120b9cc7850535196ce295f12c10334f808900`
  - Файл: [.env](/home/pinokew/Koha/koha-deploy/.env:95)

- `docker-compose.yaml` переведено на кастомну збірку сервісів `es`, `rabbitmq`, `memcached`:
  - `rabbitmq`: `build` з `RABBITMQ_VERSION`, image `koha-local-rabbitmq:*`
  - `es`: `build` з `ES_VERSION`, image `koha-local-es:*`
  - `memcached`: `build` з `MEMCACHED_VERSION`, image `koha-local-memcached:*`
  - Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:91)

- Залишено env-параметризацію портів і healthcheck для `koha`:
  - порти беруться з `KOHA_OPAC_PORT` / `KOHA_INTRANET_PORT`
  - healthcheck: `wget localhost:${KOHA_INTRANET_PORT}`
  - Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:5)

### 2) Dockerfile зміни під плагіни та версіонування з env

- Elasticsearch:
  - додано `ARG ES_VERSION`
  - `FROM docker.io/elasticsearch:${ES_VERSION}`
  - встановлення `analysis-icu` через `--batch`
  - Файл: [elasticsearch/Dockerfile](/home/pinokew/Koha/koha-deploy/elasticsearch/Dockerfile:1)

- RabbitMQ:
  - додано `ARG RABBITMQ_VERSION`
  - `FROM docker.io/rabbitmq:${RABBITMQ_VERSION}`
  - офлайн-увімкнення `rabbitmq_stomp` і `rabbitmq_web_stomp`
  - Файл: [rabbitmq/Dockerfile](/home/pinokew/Koha/koha-deploy/rabbitmq/Dockerfile:1)

- Memcached:
  - додано окремий Dockerfile
  - `ARG MEMCACHED_VERSION`
  - `FROM docker.io/memcached:${MEMCACHED_VERSION}`
  - Файл: [memcached/Dockerfile](/home/pinokew/Koha/koha-deploy/memcached/Dockerfile:1)

### 3) Env-модель для side-сервісів

- У `.env` додано/оновлено:
  - `ES_VERSION`, `RABBITMQ_VERSION`, `MEMCACHED_VERSION`
  - `ES_IMAGE=koha-local-es:8.19.6`
  - `RABBITMQ_IMAGE=koha-local-rabbitmq:3-management`
  - `MEMCACHED_IMAGE=koha-local-memcached:1.6`
  - Файл: [.env](/home/pinokew/Koha/koha-deploy/.env:97)

- У `.env.example` синхронізовано приклади:
  - додано `*_VERSION` та локальні `*_IMAGE` для built-образів
  - Файл: [.env.example](/home/pinokew/Koha/koha-deploy/.env.example:45)

### 4) Restore-пайплайн (стабілізація після інцидентів)

- Оновлено `scripts/restore.sh`:
  - введено `RESTORE_ES_DATA` (дефолт `false`)
  - за замовчуванням **не** відновлюється сирий `es_data.tar.gz`, ES-том очищується і далі робиться rebuild
  - додано `wait_service_healthy()` для контрольованого старту `es` і `koha`
  - виправлено очистку томів на безпечний `find ... -mindepth 1`
  - права для `koha_config`: `root:${KOHA_CONF_GID}`, dirs `2775`, files `640`
  - додано `normalize_koha_conf_memcached()` для нормалізації `memcached_servers` у `koha-conf.xml`
  - повторна нормалізація `memcached_servers` після старту `koha` (щоб перекривати можливий перезапис під час `koha-create`)
  - Файл: [scripts/restore.sh](/home/pinokew/Koha/koha-deploy/scripts/restore.sh:14)

### 5) Перевірки після розгортання (факт)

- Після rebuild/перезапуску:
  - `koha` image: новий digest `ca281d...`
  - `es` image: `koha-local-es:8.19.6`
  - `rabbitmq` image: `koha-local-rabbitmq:3-management`
  - `memcached` image: `koha-local-memcached:1.6`

- Runtime верифікація:
  - ES plugin list: `analysis-icu` присутній
  - RabbitMQ plugins: `rabbitmq_stomp`, `rabbitmq_web_stomp` увімкнені
  - `koha-conf.xml`: `<memcached_servers>memcached:11211</memcached_servers>`
  - `koha-elasticsearch --rebuild -v library` відпрацював
  - індекси ES після rebuild:
    - `koha_library_biblios`: `count=14`
    - `koha_library_authorities`: `count=0` (у БД `auth_header=0`)

### 6) Поетапне відновлення, що було протестовано

- Прогнано шарове відновлення:
  - `DB only` (`koha_library.sql`) -> `koha healthy`
  - `DB + koha_config` -> `koha healthy`
  - окремо `koha_data.tar.gz` -> `koha healthy`

- Висновки:
  - проблема відсутності записів у каталозі була не у втраті DB-даних, а у зламаному ES-шарі (плагіни/індекси).
  - проблема memcached warning була у runtime-конфігу `koha-conf.xml` з `127.0.0.1:11211`.

### 7) Clean restore test на тимчасових томах (завершено)

- Створено тимчасовий env-файл `.env.restoretest` зі зміною тільки `VOL_*` шляхів на:
  - `/srv/koha-volumes-restoretest/*`
- На test-volumes піднято чисту `db` і підтверджено порожню схему перед restore (`0` таблиць).
- Виконано відновлення:
  - `ENV_FILE=.env.restoretest ./scripts/restore.sh --source /var/backups/koha/2026-02-28_16-33-28 --yes`
- Після restore:
  - `db/es/rabbitmq/koha/tunnel` у стані `running/healthy`
  - `DB biblio count = 14`
  - `ES koha_library_biblios/_count = 14`
- Після ручної перевірки:
  - `.env.restoretest` видалено
  - `/srv/koha-volumes-restoretest` видалено
  - стек перезапущено назад на основному `.env`

### 8) Roadmap 1.1: секрети та базова безпека

- Додано mandatory secret scan у CI:
  - workflow `secret-scan` на `pull_request` і `push` у `main`
  - локальна перевірка hygiene + `gitleaks`
  - Файл: [.github/workflows/secret-scan.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/secret-scan.yml:1)

- Додано локальний скрипт перевірки секрет-гігієни:
  - перевіряє, що `.env` не відслідковується git
  - перевіряє відсутність `.env` у build contexts
  - перевіряє наявність `.dockerignore` в `rabbitmq/elasticsearch/memcached`
  - Файл: [scripts/check-secrets-hygiene.sh](/home/pinokew/Koha/koha-deploy/scripts/check-secrets-hygiene.sh:1)

- Мінімізовано build context для локально збираємих side-сервісів:
  - Файли:
    - [rabbitmq/.dockerignore](/home/pinokew/Koha/koha-deploy/rabbitmq/.dockerignore:1)
    - [elasticsearch/.dockerignore](/home/pinokew/Koha/koha-deploy/elasticsearch/.dockerignore:1)
    - [memcached/.dockerignore](/home/pinokew/Koha/koha-deploy/memcached/.dockerignore:1)

- Додано конфіг `gitleaks` з allowlist для шаблонних значень:
  - Файл: [.gitleaks.toml](/home/pinokew/Koha/koha-deploy/.gitleaks.toml:1)

- Перевірено (факт):
  - `docker compose ps`: `koha/db/es/rabbitmq` у стані `healthy`
  - `bash scripts/check-secrets-hygiene.sh`: `OK`

### 9) Roadmap v2 (пропозиція покращень для production)

- Підготовлено окремий оновлений roadmap із фокусом на:
  - стабільність production і runtime hardening
  - легкокерованість (runbooks, one-command operations, CI/CD gate)
  - продуктивність (DB/memcached/plack tuning на основі метрик)
- Враховано побажання: виконані пункти винесені у HTML-коментарі `<!-- -->`.
- Файл: [ROADMAP_PROD.md](/home/pinokew/Koha/koha-deploy/ROADMAP_PROD.md:1)

### 10) Roadmap v2: явні DevOps/Best Practices принципи

- Додано обов'язковий блок принципів виконання roadmap:
  - SSOT + IaC
  - immutable artifacts
  - shift-left security
  - least privilege
  - observability first
  - automated rollback
  - DR by practice
  - runbook-driven ops
  - SLO-driven tuning
  - change discipline
- Файл: [ROADMAP_PROD.md](/home/pinokew/Koha/koha-deploy/ROADMAP_PROD.md:9)

### 11) Roadmap 1.2 (поетапно): крок 1/5 `no-new-privileges`

- Для сервісів `koha`, `db`, `rabbitmq`, `es`, `memcached`, `tunnel` додано:
  - `security_opt: ["no-new-privileges:true"]`
- Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:2)

- Перевірено (факт):
  - `docker compose config -q` проходить без помилок.
  - у рендері `docker compose config` присутній `no-new-privileges:true` для всіх 6 сервісів.

### 12) Roadmap 1.2 (поетапно): крок 2/5 `cap_drop: ["ALL"]`

- Для сервісів `es`, `memcached`, `tunnel` додано:
  - `cap_drop: ["ALL"]`
- Для `koha`, `db`, `rabbitmq` `cap_drop` тимчасово прибрано через несумісність entrypoint/runtime при поточних правах/UID-переходах.
- Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:2)

- Перевірено (факт):
  - `docker compose config -q` проходить без помилок.
  - у рендері `docker compose config` присутній `cap_drop: ALL` для `es`, `memcached`, `tunnel`.

### 13) Інцидент після hardening кроку 2/5 і виправлення

- Симптом:
  - `rabbitmq` і `db` переходили в restart loop після `docker compose up -d`.

- Root cause:
  - `cap_drop: ALL` для `rabbitmq` і `db` зламав entrypoint-операції зі зміною UID/GID та доступом до data paths:
    - `rabbitmq`: `failed switching to "rabbitmq": operation not permitted`
    - `db`: `find: '/var/lib/mysql/': Permission denied`

- Виправлення:
  - прибрано `cap_drop` з `koha`, `db`, `rabbitmq`;
  - залишено `cap_drop: ALL` лише для сумісних сервісів: `es`, `memcached`, `tunnel`.

- Перевірено (факт):
  - `docker compose up -d` відпрацював успішно.
  - `docker compose ps -a`: `db`, `rabbitmq`, `koha`, `es` у стані `healthy`.

### 14) Roadmap 1.2 (поетапно): крок 3/5 (частина A) `pids_limit + ulimits`

- Для всіх сервісів `koha`, `db`, `rabbitmq`, `es`, `memcached`, `tunnel` додано:
  - `pids_limit: 1024`
  - `ulimits.nofile.soft: 65536`
  - `ulimits.nofile.hard: 65536`
- Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:2)

- Перевірено (факт):
  - `docker compose config -q` проходить без помилок.
  - `docker compose up -d` пройшов успішно.
  - `docker compose ps -a`: `db`, `rabbitmq`, `koha`, `es` у стані `healthy`.

- Примітка:
  - Параметри `mem_limit` та `cpus` винесено в наступний підкрок (окремо), щоб не ризикувати стабільністю після попереднього інциденту.

### 15) Roadmap 1.2 (поетапно): крок 3/5 (частина B) `mem_limit + cpus`

- Додано resource limits у `docker-compose.yaml` через env з дефолтами:
  - `koha`: `mem_limit=2g`, `cpus=1.50`
  - `db`: `mem_limit=2g`, `cpus=1.50`
  - `rabbitmq`: `mem_limit=512m`, `cpus=1.00`
  - `es`: `mem_limit=1g`, `cpus=1.00`
  - `memcached`: `mem_limit=256m`, `cpus=0.50`
  - `tunnel`: `mem_limit=128m`, `cpus=0.25`
- Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:2)

- У `.env.example` додано відповідні опційні ключі для тюнінгу без правок compose:
  - `*_MEM_LIMIT`, `*_CPUS`
- Файл: [.env.example](/home/pinokew/Koha/koha-deploy/.env.example:77)

- Перевірено (факт):
  - `docker compose config -q` проходить без помилок.
  - `docker compose up -d` пройшов успішно.
  - `docker compose ps -a`: `db`, `rabbitmq`, `koha`, `es` у стані `healthy`.
  - `docker inspect` підтвердив застосування memory/cpu/pids/nofile лімітів до всіх 6 сервісів.

### 16) Roadmap 1.2 (поетапно): крок 4/5 `logging rotation`

- Для всіх сервісів `koha`, `db`, `rabbitmq`, `es`, `memcached`, `tunnel` додано:
  - `logging.driver: json-file`
  - `logging.options.max-size: ${LOG_MAX_SIZE:-10m}`
  - `logging.options.max-file: ${LOG_MAX_FILE:-3}`
- Файл: [docker-compose.yaml](/home/pinokew/Koha/koha-deploy/docker-compose.yaml:2)

- У `.env.example` додано опційні параметри:
  - `LOG_MAX_SIZE=10m`
  - `LOG_MAX_FILE=3`
- Файл: [.env.example](/home/pinokew/Koha/koha-deploy/.env.example:83)

- Перевірено (факт):
  - `docker compose config -q` проходить без помилок.
  - `docker compose up -d` пройшов успішно.
  - `docker compose ps -a`: `db`, `rabbitmq`, `koha`, `es` у стані `healthy`.
  - `docker inspect` підтвердив для всіх 6 сервісів: `type=json-file`, `max-size=10m`, `max-file=3`.

### 17) Ротація changelog на томи

- Детальний `CHANGELOG.md` перенесено в:
  - [CHANGELOG_2026_VOL_01.md](/home/pinokew/Koha/koha-deploy/CHANGELOGS/CHANGELOG_2026_VOL_01.md)
- `CHANGELOG.md` переформатовано як короткий індекс томів:
  - активний том
  - політика ротації
  - формат іменування файлів
- Додано правила ведення changelog-томів у:
  - [NEW_CHAT_START_HERE.md](/home/pinokew/Koha/koha-deploy/NEW_CHAT_START_HERE.md)

- Ліміти тома:
  - `soft limit`: 300 рядків
  - `hard limit`: 350 рядків

### 18) Roadmap 1.2 (поетапно): крок 5/5 `policy: internal services without published ports`

- Додано policy-check скрипт:
  - [scripts/check-internal-ports-policy.sh](/home/pinokew/Koha/koha-deploy/scripts/check-internal-ports-policy.sh)
  - перевіряє, що `ports:` визначені лише для дозволених сервісів (за замовчуванням тільки `koha`).
  - при порушенні повертає non-zero і блокує CI.

- Додано CI guard у workflow `secret-scan`:
  - крок `Internal ports policy check`
  - Файл: [.github/workflows/secret-scan.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/secret-scan.yml:29)

- Перевірено (факт):
  - `bash scripts/check-internal-ports-policy.sh` -> `OK`.
  - Поточний `docker-compose.yaml` відповідає policy: published ports є лише у `koha`.
