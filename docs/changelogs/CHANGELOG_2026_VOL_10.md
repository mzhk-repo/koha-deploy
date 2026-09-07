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
