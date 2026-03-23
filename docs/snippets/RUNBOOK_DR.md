# DR Runbook (Backup, Restore, PITR)

Дата: 2026-02-28
Сфера: Koha stack (`db`, `koha`, `es`, `rabbitmq`, `memcached`)

## 1. Цілі

- RPO (ціль): до 24 годин (або менше при частішому запуску backup).
- RTO (ціль): до 2 годин для full restore + reindex.

Параметри RPO/RTO мають бути підтверджені регулярним restore-test (мінімум щомісяця).

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

Значення в `.env`:

- `BACKUP_PATH=/var/backups/koha` (повний backup set)
- `BACKUP_OFFSITE_PATH=/home/pinokew/GoogleDrive/kdv-drive/KDV_Backups/Koha` (легка offsite-копія)
- `BACKUP_OFFSITE_EXCLUDE_FILES=koha_data.tar.gz` (виключення важкого медіа-архіву; список через кому)
- `DB_LOG_BIN_BASENAME=mysql-bin`
- `DB_BINLOG_FORMAT=ROW`
- `DB_SYNC_BINLOG=1`
- `DB_BINLOG_EXPIRE_DAYS=7`

## 4. Регулярний backup

Ручний запуск:

```bash
./scripts/backup.sh
```

Рекомендований cron (щодня 02:15):

```cron
15 2 * * * cd /home/pinokew/Koha/koha-deploy && ./scripts/backup.sh >> /var/log/koha-backup.log 2>&1
```

## 5. Dry-run перевірка backup set

```bash
./scripts/restore.sh --source /path/to/backup_dir --dry-run
```

Що перевіряє dry-run:

- цілісність (`sha256sum -c`, якщо є `SHA256SUMS`)
- валідність SQL та `.tar.gz` артефактів
- наявність обов'язкового SQL дампу

## 6. Full restore (DB + файли + reindex)

```bash
./scripts/restore.sh --source /path/to/backup_dir --yes
```

Скрипт виконує:

1. `docker compose down`
2. restore `koha_config` + `koha_data`
3. очистка DB/ES volume (або restore ES raw data, якщо увімкнено)
4. старт `db`, імпорт SQL
5. старт `es/rabbitmq/memcached/koha`
6. `koha-elasticsearch --rebuild`
7. verify (DB count + ES count)

## 7. PITR restore (до timestamp)

Приклад:

```bash
./scripts/restore.sh \
  --source /path/to/backup_dir \
  --pitr-datetime "2026-02-28 12:30:00" \
  --yes
```

Вимоги для PITR:

- у backup set має бути `mariadb_binlogs.tar.gz`
- бажано `pitr_master_status.env` для коректного старту реплею binlog

## 8. Післяаварійна перевірка

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

## 9. Restore-test (щомісячно)

Мінімальний протокол:

1. Взяти останній backup set.
2. `scripts/restore.sh --dry-run`.
3. `scripts/restore.sh --yes` у тестовому середовищі.
4. Зафіксувати фактичні:
   - старт restore
   - час готовності сервісів
   - час завершення reindex
   - RTO
5. Перевірити доступність каталогу, авторизацію, ключові workflows.
6. Занести результат у журнал інцидентів/операцій.

## 10. Типові збої і дії

- ES rebuild впав на `icu_folding`:
  - перевірити `analysis-icu` у ES (`elasticsearch-plugin list`)
- Koha показує memcached `127.0.0.1`:
  - перевірити `koha-conf.xml` і `MEMCACHED_SERVERS` в `.env`
- RabbitMQ fallback (SQL polling):
  - перевірити плагіни `rabbitmq_stomp` / `rabbitmq_web_stomp`
