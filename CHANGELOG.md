# CHANGELOG Index

Це індекс томів changelog. Детальні записи ведуться у `CHANGELOGS/`.

## Поточний активний том

1. [CHANGELOG_2026_VOL_02.md](/home/pinokew/Koha/koha-deploy/CHANGELOGS/CHANGELOG_2026_VOL_02.md)
   - Статус: active
   - Рядків: ~120
   - Контекст: перехід до roadmap 1.3 (Identity/OIDC lockdown), поетапна імплементація

2. [CHANGELOG_2026_VOL_01.md](/home/pinokew/Koha/koha-deploy/CHANGELOGS/CHANGELOG_2026_VOL_01.md)
   - Статус: archived
   - Рядків: ~292
   - Контекст: старт production hardening, roadmap 1.1 і 1.2 (поетапно), DR/restore стабілізація

## Політика ротації

1. `soft limit`: 300 рядків на том.
2. `hard limit`: 350 рядків на том.
3. Коли том досягає `~300` рядків, створюється наступний том (`VOL_NN`) з короткою анотацією на початку.
4. Нові записи додаються тільки в активний том.
5. У цей індекс додається новий запис про том (статус, контекст, посилання).

## Формат імені файлу

`CHANGELOGS/CHANGELOG_<YEAR>_VOL_<NN>.md`

Приклад: `CHANGELOGS/CHANGELOG_2026_VOL_02.md`
