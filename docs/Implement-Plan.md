# Усунення destructive Koha schema import

## Підсумок

- Першопричина підтверджена: `07-db-import.sh` в образі трактує будь-яку помилку SQL, включно з тимчасовим `Unknown server host 'db'`, як порожню БД.
- Після невдалого probe скрипт імпортує `kohastructure.sql`, який містить `DROP TABLE IF EXISTS` і видаляє наявні таблиці та дані. [Офіційний Koha schema-файл](https://github.com/Koha-Community/Koha/blob/main/installer/data/mysql/kohastructure.sql).
- Swarm не дотримується `depends_on`; тому під час reboot/deploy виникає race між стартом `koha` та DNS/готовністю `db`.
- Втрата 27 серпня збігається з успішним повторним імпортом: усі 277 таблиць створені о `11:59:06`. Post-deploy patch-скрипти не є джерелом видалення — вони запускаються вже після startup pipeline.
- Політика: автоматичний schema import повністю забороняється; нова БД створюється тільки через Web installer або штатний restore.

## Зміни

### Image repo `/opt/Koha/koha-docker-build`

- Перетворити `07-db-import.sh` на безпечний no-op із повідомленням, що автоматичний імпорт вимкнений і для ініціалізації треба використовувати installer/restore.
- Прибрати з runtime-кроку всі виклики `koha-mysql`, пошук `kohastructure.sql` та SQL pipeline.
- Додати policy-check, який падає, якщо `07-db-import.sh` знову містить `kohastructure.sql`, `DROP TABLE` або передачу SQL у `koha-mysql`; підключити його до наявного `deploy-orchestrator.sh`.
- Оновити README, ARCHITECTURE та активний `CHANGELOGS/CHANGELOG_2026_VOL_02.md`: зафіксувати fail-safe policy і зміну контракту першого запуску.

### Deploy repo `/opt/Koha/koha-deploy`

- У `docker-compose.yml` і Swarm override завжди додавати `07-db-import.sh` до `KOHA_SETUP_SKIP_STEPS`, незалежно від значення з env. Це негайно захистить старий опублікований образ і збережеться у service spec після reboot.
- Перед `bootstrap-live-configs.sh` додати post-deploy DB guard: `systempreferences.Version` має існувати й бути непорожнім. Помилка з’єднання, відсутня таблиця або відсутній `Version` зупиняють deploy до будь-яких syspref UPSERT.
- Для порожньої нової БД stack лишається доступним для Web installer, але deploy завершується fail-closed; після installer оператор повторює deploy. Restore залишається штатною альтернативою.
- Додати regression test, який перевіряє примусовий skip у звичайному та Swarm manifests і порядок DB guard перед post-deploy patch modules.
- Оновити `.env.example`, `docs/ARCHITECTURE.md` та активний `docs/changelogs/CHANGELOG_2026_VOL_09.md`.

## Перевірка

- Image repo: `bash -n`, ShellCheck, новий DB-import safety check, наявні policy checks і локальний Docker build.
- Deploy repo: regression tests, `bash -n`, ShellCheck, `docker compose config` для Compose та Swarm; rendered `koha` environment обов’язково містить `07-db-import.sh`.
- Негативні сценарії:
  - DNS `db` недоступний — жоден SQL import не виконується;
  - БД порожня — жоден SQL import не виконується, post-deploy guard завершує deploy помилкою;
  - `systempreferences` існує без `Version` — patch modules не запускаються;
  - встановлена БД — deploy і patch modules працюють штатно.
- Після відновлення dev-БД: зафіксувати `Version`, кількість `biblio`/`borrowers` і checksum SQL dump; виконати контрольний reboot dev-хоста та підтвердити незмінність значень.

## Rollout та припущення

- Спочатку розгорнути deploy-level skip на dev-хості зі старим образом.
- Потім зібрати й опублікувати виправлений образ з immutable digest, оновити `KOHA_IMAGE` у dev та виконати контрольний reboot.
- Після успішного dev-тесту окремо погодити production deploy та оновити production digest.
- Відновлення втраченої БД і reboot є окремими state-changing операціями та виконуються лише після явного підтвердження.
- Зміна image repo потребуватиме доступу на запис поза поточним writable root.
