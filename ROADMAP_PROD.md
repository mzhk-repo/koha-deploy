Roadmap: Koha Production Hardening and Performance (v2)

Дата оновлення: 2026-02-28

Ціль: стабільний, керований і продуктивний production з передбачуваним деплоєм та відновленням.

Принципи:
1. Спочатку усуваємо ризики простою і втрати даних.
2. Потім закриваємо керованість (процеси, CI/CD, спостережуваність).
3. Потім системно тюнимо продуктивність на основі метрик, а не "на око".

Обов'язкові DevOps/Best Practices (для всіх кроків roadmap):
1. SSOT + IaC: production-конфігурація відтворювана через репозиторій/compose/env-шаблони, без "ручних магічних правок" у контейнерах.
2. Immutable artifacts: один і той самий digest проходить шлях `dev -> stage -> prod`, без rebuild "на льоту" в проді.
3. Shift-left security: перевірки безпеки і секретів блокують merge до `main`.
4. Least privilege: мінімальні права в CI, контейнерах і доступах операторів.
5. Observability first: кожна критична зміна має healthcheck/метрику/лог і алерт.
6. Automated rollback: для кожного релізу є чітка команда/процедура повернення.
7. DR by practice: restore/PITR перевіряються регулярно, не лише декларуються.
8. Runbook-driven ops: інциденти закриваються за короткими runbook'ами і постмортемом.
9. SLO-driven tuning: продуктивність тюнимо за SLI/SLO (p95 latency, error rate, saturation), а не за суб'єктивними відчуттями.
10. Change discipline: кожна суттєва зміна фіксується у `CHANGELOG.md` з фактом перевірки.

<!--
ВИКОНАНО (залишено в коментарях за домовленістю):

1.1 Секрети та базова безпека
- .env не комітиться, додані перевірки hygiene.
- Додано mandatory secret scan (gitleaks) у CI.
- Додано реєстр секретів і runbook ротації.

1.6 DR/Backup + PITR
- Реалізовані scripts/backup.sh і scripts/restore.sh.
- Є dry-run/full restore/PITR verify.
- Є автоматичний ES rebuild після restore.
- Є DR runbook і підтверджений restore test.
-->

# 1) Blocking перед go-live

## 1.1 SDLC та захищений CI/CD
Що робимо:
1. Увімкнути branch protection для `main`: no direct push, required review, required checks.
2. Додати обов'язкові CI-перевірки: `hadolint`, `shellcheck`, `trivy config`, `trivy image`, `secret-scan`.
3. Для critical workflows пінити `uses:` на commit SHA.
4. Мінімізувати `permissions` у workflows, додати `concurrency`.

DoD:
1. Жоден PR не мержиться без review та повного зеленого набору checks.
2. Усі security checks блокують merge при помилці.

<!-- ## 1.2 Runtime hardening та ізоляція мережі
Що робимо:
1. Додати для сервісів `security_opt: ["no-new-privileges:true"]`.
2. Додати `cap_drop: ["ALL"]` там, де можливо; залишити лише необхідні cap.
3. Додати `pids_limit`, `mem_limit`, `cpus` і `ulimits` для `koha/db/es/rabbitmq/memcached`.
4. Увімкнути `logging` rotation (`max-size`, `max-file`) для всіх сервісів.
5. Зафіксувати policy: внутрішні сервіси без published ports.

DoD:
1. Контейнери мають обмеження ресурсів і безпечні security-політики.
2. Логи не переповнюють диск. -->

<!-- ## 1.3 Identity/OIDC lockdown
Що робимо:
1. Примусово вимкнути локальне відновлення/зміну пароля (`OpacResetPassword`, `OpacPasswordChange`).

DoD:
1. Користувач opac не може зміниnb пароль. -->

## 1.4 Supply-chain базовий мінімум
Що робимо:
1. Публікувати deploy-образи як immutable (`sha256:digest`), без `latest`.
2. Для deploy-repo прибрати `build` у production-флоу і перейти на підготовлені image/digest.
3. Додати SBOM + Trivy image scan як обов'язкові артефакти релізу.

DoD:
1. Production запускається тільки на immutable images.
2. Кожен реліз має SBOM і пройдений image scan.

## 1.5 Спостережуваність (мінімум)
Що робимо:
1. Центральний збір логів (наприклад, Promtail + Loki + Grafana або ELK).
2. Базові метрики: host, containers, MariaDB, RabbitMQ, Elasticsearch.
3. Алерти: healthcheck down, 5xx spike, low disk, high memory/cpu, backup/restore fail.
4. Uptime моніторинг OPAC/Staff/API з нотифікаціями.

DoD:
1. Оператор отримує алерт раніше за користувача.
2. Є дашборди для інцидент-діагностики без ручного SSH "наосліп".

# 2) Performance baseline (обов'язково перед піковим навантаженням)

## 2.1 MariaDB tuning
Що робимо:
1. Ввести параметризований тюнінг через env або окремий конфіг: `max_connections`, `innodb_buffer_pool_size`, `innodb_log_file_size`.
2. Увімкнути slow query log з ротацією.
3. Зафіксувати допустимі пороги latency для ключових запитів Koha.

DoD:
1. p95 DB latency і p95 web response в межах погоджених SLO.
2. Є список топ-10 повільних запитів і план оптимізації.

## 2.2 Memcached tuning
Що робимо:
1. Задати memory limit (наприклад `-m 256`) і `-c` (max connections).
2. Моніторити hit ratio і eviction rate.

DoD:
1. Hit ratio стабільно на цільовому рівні (узгодити, наприклад >= 0.80).
2. Немає масових eviction під робочим навантаженням.

## 2.3 Koha/Plack workers
Що робимо:
1. Винести параметри workers/max_requests у SSOT (`.env`).
2. Провести короткий load test на типових сценаріях OPAC і staff.

DoD:
1. Пікові сценарії не викликають деградацію або рестарти контейнера.
2. Є рекомендовані production-значення workers для поточної інфраструктури.

# 3) Керованість і операційна простота

## 3.1 Операційні сценарії в один крок
Що робимо:
1. Додати уніфіковані скрипти `scripts/up.sh`, `scripts/down.sh`, `scripts/healthcheck.sh`, `scripts/update-image.sh`.
2. Стандартизувати pre-flight/post-flight перевірки перед деплоєм.
3. Додати scripts/verify-env.sh, який перевірятиме наявність усіх необхідних ключів у .env перед запуском up.sh.

DoD:
1. Будь-яка типова операція запускається однією командою.
2. Помилки в деплої виявляються pre-flight перевірками.

## 3.2 Runbooks P1/P2
Що робимо:
1. Додати окремі runbooks: `DB down`, `RabbitMQ backlog`, `Disk full`, `SSO down`.
2. Для кожного: симптоми, діагностика, rollback, критерії ескалації.

DoD:
1. Новий оператор може пройти інцидент за чеклістом без втрати контексту.

# 4) Go-live gate (оновлений)

Go-live дозволений лише коли одночасно виконано:
1. Security: секрети, ротація, mandatory scans.
2. Delivery: branch protection + required checks + immutable images.
3. Runtime: hardening, limits, healthchecks, log rotation.
4. Recovery: регулярний restore test + підтверджений PITR.
5. Observability: алерти та дашборди на критичні сценарії.
6. Performance: зафіксовані базові SLO і пройдений load/smoke тест.

# 5) Після go-live (30/60/90 днів)

30 днів:
1. Підкрутити DB/memcached/plack за фактичними метриками.
2. Закрити топ-інциденти з перших тижнів.

60 днів:
1. Додати автогенерацію release notes і change approvals.
2. Розширити SLI/SLO/error-budget.

90 днів:
1. Повний security review (policy, IAM, audit trail).
2. Повторний capacity planning на наступний період.
