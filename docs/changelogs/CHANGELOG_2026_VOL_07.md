### 25) Swarm deploy: виправлено причини `0/1` для Koha-adjacent сервісів

- Контекст:
  - `docker stack deploy` успішно створював `koha_db`, але `koha_koha`, `koha_es`, `koha_rabbitmq` і `koha_memcached` лишались `0/1`;
  - `koha_koha` відхилявся через відсутній bind source `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - `es`, `rabbitmq` і `memcached` відхилялись через локальні `koha-local-*` images у Swarm.

- Оновлено:
  - `.gitignore`
  - `scripts/init-volumes.sh`
  - `scripts/deploy-orchestrator-swarm.sh`
  - `docker-compose.swarm.yml`
  - `rabbitmq/enabled_plugins`

- Зміни:
  - `init-volumes.sh` тепер створює і нормалізує `${VOL_KOHA_CONF}/${KOHA_INSTANCE}`;
  - Swarm timeout у deploy-orchestrator тепер друкує `docker service ps <service> --no-trunc`;
  - deploy-orchestrator перед `stack deploy` build-ить локальний image для `es` (`ORCHESTRATOR_SWARM_BUILD_SERVICES`, default: `es`), бо Elasticsearch потребує `analysis-icu`;
  - після `stack deploy` deploy-orchestrator виконує smart reconcile: `docker service update --force` запускається тільки для сервісів без running container, з rejected/failed task-ами або зі зміненим локально зібраним image;
  - ручний override лишився через `ORCHESTRATOR_SWARM_FORCE_UPDATE_SERVICES`; reconcile можна вимкнути через `ORCHESTRATOR_SWARM_RECONCILE=off` або примусити через `ORCHESTRATOR_SWARM_RECONCILE=force`;
  - cleanup deploy-orchestrator прибирає temp-файли `.koha.env.*`, `.koha.stack.raw.*.yml`, `.koha.stack.deploy.*.yml`;
  - `.gitignore` ігнорує temp env/manifest артефакти Swarm deploy;
  - `init-volumes.sh` додає ACL для поточного host runner на `${VOL_KOHA_CONF}`, щоб live config patch scripts могли читати й оновлювати `koha-conf.xml`, який створюється container user/group;
  - `rabbitmq` у Swarm переведено на офіційний `docker.io/rabbitmq:${RABBITMQ_VERSION:-3-management}`;
  - RabbitMQ plugins (`rabbitmq_management`, `rabbitmq_stomp`, `rabbitmq_web_stomp`) передаються через Docker Config;
  - `memcached` у Swarm переведено на офіційний `docker.io/memcached:${MEMCACHED_VERSION:-1.6}`.

- Перевірено:
  - `bash -n scripts/init-volumes.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `shellcheck scripts/init-volumes.sh scripts/deploy-orchestrator-swarm.sh` - OK;
  - `docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.swarm.yml config` - OK;
  - `ORCHESTRATOR_MODE=noop bash scripts/deploy-orchestrator-swarm.sh` - OK.

### 26) Koha live config: додано патч DB credentials перед runtime verify

- Контекст:
  - після виправлення Swarm mount/image проблем `koha_koha` створював container, але health лишався `starting`;
  - логи Koha показували `Access denied for user 'koha_db'` і `Access refused for user 'koha_mq'`;
  - live `koha-conf.xml` у volume містив застарілі/default credentials, а bootstrap verify не перевіряв секретні поля.

- Оновлено:
  - `scripts/bootstrap-live-configs.sh`
  - `scripts/patch/patch-koha-conf-xml-db.sh`
  - `scripts/patch/patch-koha-conf-xml-verify.sh`

- Зміни:
  - додано модуль `db`, який патчить основний DB block у `${VOL_KOHA_CONF}/${KOHA_INSTANCE}/koha-conf.xml` з env (`DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`);
  - `bootstrap-live-configs.sh` запускає `db` перед іншими live config модулями;
  - `patch-koha-conf-xml-verify.sh` тепер перевіряє DB connection block і secret-поля DB/RabbitMQ без виводу секретів у stdout або CLI args.

- Перевірено:
  - `bash -n scripts/bootstrap-live-configs.sh scripts/patch/patch-koha-conf-xml-db.sh scripts/patch/patch-koha-conf-xml-verify.sh` - OK;
  - `shellcheck scripts/bootstrap-live-configs.sh scripts/patch/patch-koha-conf-xml-db.sh scripts/patch/patch-koha-conf-xml-verify.sh` - OK;
  - `bash scripts/bootstrap-live-configs.sh --list-modules` - OK;
  - `bash scripts/patch/patch-koha-conf-xml-db.sh --env-file .env.example --dry-run --no-wait` - OK;
  - `git diff --check` - OK.

- Runtime-перевірка:
  - live `koha-conf.xml` пропатчено з актуального Swarm secret payload без друку секретів;
  - `docker service update --force koha_koha` завершився convergence;
  - `koha_koha` перейшов у `1/1`, container health: `healthy`;
  - HTTP-перевірка всередині container: `wget -q --spider http://localhost:${KOHA_INTRANET_PORT:-8081}` - OK.
