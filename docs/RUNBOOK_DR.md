# DR Runbook (Backup, Restore, PITR)

Дата: 2026-02-28
Сфера: Koha stack (`db`, `koha`, `es`, `rabbitmq`, `memcached`)

## 1. Цілі

- RPO (ціль): до 24 годин (або менше при частішому запуску backup).
- RTO (ціль): до 2 годин для full restore + reindex.

Параметри RPO/RTO мають бути підтверджені регулярним restore-test (мінімум щомісяця).

## 1.1. Baseline Koha sessions → Memcached

Readonly snapshot для Ітерації 0 дорожньої карти, знятий 2026-09-12 14:34 UTC
(17:34 за Europe/Kyiv) із запущеного Swarm-стеку `koha`:

- MariaDB `sessions`: `COUNT(*)=2,033,162`.
- Розмір таблиці за `information_schema`: `data_length=475,004,928` bytes
  (приблизно 453 MiB); `index_length=0`.
- Binlog: `mysql-bin.000009:2224172`; `log_bin=ON`; `binlog_format=ROW`;
  retention `604800` seconds / 7 днів.
- Розмір raw binlog-файлів, створених 2026-09-07—2026-09-12
  (`mysql-bin.000001`—`mysql-bin.000009`, без `.idx`): `1,203,022,994` bytes
  (приблизно 1,147 MiB / 1.12 GiB).
- Memcached: `curr_items=61`, `bytes=11,420`, `evictions=0`.

Це readonly baseline; deploy, restore, очищення `sessions` і зміна grants не
виконувалися. Binlog position отримано через runtime Docker Secret без виводу
його значення.

### Результат Ітерації 5

2026-09-12 у dev mirror після підтвердження `SessionStorage=memcached` і
успішного Memcached roundtrip виконано через `koha-mysql`:

```sql
TRUNCATE TABLE sessions;
```

- До очищення: `2,033,351` рядків; binlog `mysql-bin.000010:71744`.
- Після очищення: `COUNT(*)=0`; binlog `mysql-bin.000010:71884`.
- Новий binlog event: одна коротка Query-подія `TRUNCATE TABLE sessions`.
- Memcached після операції: `evictions=0`; Memcached не перезапускався і не
  очищався.

## 2. Що саме бекапиться

`scripts/backup.sh` створює backup set:

- SQL дамп MariaDB (`<DB_NAME>.sql.gz`)
- `koha_config.tar.gz`
- `koha_data.tar.gz`
- `koha_logs.tar.gz` (опційно)
- `mariadb_binlogs.tar.gz` (для PITR)
- PITR metadata (`pitr_master_status.env`, `pitr_master_status.txt`, `mariadb_binlog_variables.txt`)
- `SHA256SUMS`, `backup_manifest.tsv`, `backup_metadata.env`

Примітка: raw Elasticsearch data за замовчуванням **не** бекапиться (`BACKUP_INCLUDE_ES_DATA=false`). Після restore виконується rebuild індексів.

## 3. Налаштування

Значення в `env.dev.enc` / `env.prod.enc`:

- `BACKUP_PATH=/var/backups/koha` (повний backup set)
- `BACKUP_RCLONE_REMOTE=koha-backups` (назва remote з `rclone config`)
- `BACKUP_RCLONE_FOLDER=KDV_Backups/Koha` (папка всередині remote; можна залишити порожньою для кореня remote)
- `BACKUP_RCLONE_RETENTION_DAYS=0` (окремий retention для Google Drive/rclone; `0` = вимкнено)
- `BACKUP_OFFSITE_EXCLUDE_FILES=koha_data.tar.gz` (виключення важкого медіа-архіву; список через кому)
- `DB_LOG_BIN_BASENAME=mysql-bin`
- `DB_BINLOG_FORMAT=ROW`
- `DB_SYNC_BINLOG=1`
- `DB_BINLOG_EXPIRE_DAYS=7`

## 4. Регулярний backup

Ручний запуск:

```bash
./scripts/backup.sh
# або явно:
./scripts/backup.sh --env prod
```

Рекомендований cron (щодня 02:15):

```cron
15 2 * * * cd /opt/Koha/koha-deploy && SERVER_ENV=prod ./scripts/backup.sh >> /var/log/koha-backup.log 2>&1
```

## 5. Dry-run перевірка backup set

```bash
./scripts/restore.sh --source /path/to/backup_dir --dry-run
# або явно:
./scripts/restore.sh --env prod --source /path/to/backup_dir --dry-run
```

Що перевіряє dry-run:

- цілісність (`sha256sum -c`, якщо є `SHA256SUMS`)
- валідність SQL та `.tar.gz` артефактів
- наявність обов'язкового SQL дампу

## 6. Restore smoke test

Безпечна перевірка restore без зміни production Koha DB:

```bash
./scripts/test-restore.sh --env prod
# або для конкретного backup set:
./scripts/test-restore.sh --env prod --source /path/to/backup_dir
```

Скрипт піднімає тимчасовий MariaDB container, імпортує SQL dump у тимчасову БД і видаляє контейнер/тимчасові дані після перевірки.

Textfile metrics:

- `koha_restore_smoke_last_run_timestamp_seconds`
- `koha_restore_smoke_last_success_timestamp_seconds`
- `koha_restore_smoke_last_status`

`--dry-run` не оновлює freshness metrics.

## 7. Full restore (DB + файли + reindex)

```bash
./scripts/restore.sh --source /path/to/backup_dir --yes
# або явно:
./scripts/restore.sh --env prod --source /path/to/backup_dir --yes
```

Скрипт виконує:

1. `docker compose down`
2. restore `koha_config` + `koha_data`
3. очистка DB/ES volume (або restore ES raw data, якщо увімкнено)
4. старт `db`, імпорт SQL
5. старт `es/rabbitmq/memcached/koha`
6. `koha-elasticsearch --rebuild`
7. verify (DB count + ES count)

### 7.1. Якщо після backup змінювалися DB/RabbitMQ паролі

Backup set містить `koha_config.tar.gz`, тому full restore повертає `koha-conf.xml` у стан на момент backup. Якщо після створення backup змінювалися `DB_PASS`, `DB_ROOT_PASS` або `RABBITMQ_PASS` в `env.<env>.enc`, після restore config може містити старі credentials.

Ознаки:

- `koha` довго лишається `health: starting`;
- `koha-es-indexer` падає з `task: non-zero exit (1)`;
- у логах є:
  - `Access denied for user 'koha_db'`;
  - `Access refused for user 'koha_mq'`.

Дії:

1. Оновити Swarm versioned secrets і service specs з актуального `env.<env>.enc` перед або після restore.
2. Після відновлення `koha_config.tar.gz` пропатчити live `koha-conf.xml` актуальними значеннями:

   ```bash
   ENV_TMP="$(mktemp /dev/shm/koha-env.XXXXXX)"
   chmod 600 "${ENV_TMP}"
   sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > "${ENV_TMP}"

   ./scripts/bootstrap-live-configs.sh \
     --env-file "${ENV_TMP}" \
     --modules db,message-broker,verify \
     --no-restart

   rm -f "${ENV_TMP}"
   ```

3. Якщо RabbitMQ data volume не очищувався або user вже існував, оновити пароль існуючого RabbitMQ user до значення з актуального `env.<env>.enc`:

   ```bash
   # Не source-ити decrypted dotenv напряму, якщо значення містять пробіли.
   # Використати штатний безпечний env-loader.
   . scripts/lib/autonomous-env.sh
   load_autonomous_env "$PWD" dev

   rabbit_cid="$(docker ps -q --filter label=com.docker.swarm.service.name=koha_rabbitmq | head -n 1)"
   docker exec "${rabbit_cid}" rabbitmqctl change_password "${RABBITMQ_USER}" "${RABBITMQ_PASS}"
   ```

4. Перезапустити `koha` і `koha-es-indexer`, після чого перевірити health:

   ```bash
   docker service update --force koha_koha
   docker service update --force koha_koha-es-indexer
   docker service ls | grep '^koha_'
   ```

Примітка: `chown: changing ownership of '.../koha-conf.xml': Operation not permitted` під час restore не є блокером, якщо наступний `verify` проходить і сервіси стають `healthy`.

## 8. PITR restore (до timestamp)

Приклад:

```bash
./scripts/restore.sh \
  --env prod \
  --source /path/to/backup_dir \
  --pitr-datetime "2026-02-28 12:30:00" \
  --yes
```

Вимоги для PITR:

- у backup set має бути `mariadb_binlogs.tar.gz`
- бажано `pitr_master_status.env` для коректного старту реплею binlog

## 9. Післяаварійна перевірка

Перевірити:

1. `docker compose ps` -> `db/es/rabbitmq/koha` мають бути healthy.
2. В Koha admin:
   - Search engine = Elasticsearch
   - Memcached = `memcached:11211`
   - RabbitMQ не у fallback SQL polling
3. Пошук у каталозі повертає записи.

CLI перевірки:

```bash
docker compose exec -T es sh -lc 'curl -s http://localhost:9200/_cat/indices?v | grep koha_library'
docker compose exec -T rabbitmq rabbitmq-plugins list | grep -i stomp
```

## 10. Restore-test (щомісячно)

Мінімальний протокол:

1. Взяти останній backup set.
2. `scripts/restore.sh --env dev --source <backup_dir> --dry-run`.
3. `scripts/test-restore.sh --env prod --source <backup_dir>` для smoke restore у тимчасову БД без зміни production.
4. `scripts/restore.sh --env dev --source <backup_dir> --yes` у тестовому середовищі.
5. Зафіксувати фактичні:
   - старт restore
   - час готовності сервісів
   - час завершення reindex
   - RTO
6. Перевірити доступність каталогу, авторизацію, ключові workflows.
7. Занести результат у журнал інцидентів/операцій.

## 11. Типові збої і дії

- ES rebuild впав на `icu_folding`:
  - перевірити `analysis-icu` у ES (`elasticsearch-plugin list`)
- Koha показує memcached `127.0.0.1`:
  - перевірити `koha-conf.xml` і `MEMCACHED_SERVERS` в `env.<env>.enc`
- RabbitMQ fallback (SQL polling):
  - перевірити плагіни `rabbitmq_stomp` / `rabbitmq_web_stomp`
- `koha`/`koha-es-indexer` після restore отримують `Access denied for user 'koha_db'` або `Access refused for user 'koha_mq'`:
  - перевірити, чи не були змінені `DB_PASS` / `RABBITMQ_PASS` після backup;
  - виконати процедуру з розділу `7.1`;
  - не source-ити decrypted dotenv напряму, якщо там є значення з пробілами.
