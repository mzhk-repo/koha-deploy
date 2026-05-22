### 1) Deploy fix: повернено `app_env_payload` secret для основного Koha service

- Контекст:
  - після спрощення `koha-es-indexer` помилково зник `app_env_payload` secret mount у `koha_koha`;
  - `koha_koha` падав із `cannot open /run/secrets/app_env_payload` під час Swarm reconcile.

- Оновлено:
  - `docker-compose.swarm.yml`

- Зміни:
  - `app_env_payload` secret mount повернено тільки для основного `koha` service;
  - `koha-es-indexer` лишився без secret mount і читає runtime credentials через live `koha-conf.xml`.

- Перевірено:
  - redeploy з `env.dev.enc` завершився `Swarm deploy completed`;
  - `koha_koha` running;
  - `koha_koha-es-indexer` running, всередині працює `es_indexer_daemon.pl` під `library-koha`.

### 2) Elasticsearch guard: додано CLI-прапорець примусової переіндексації

- Оновлено:
  - `scripts/koha-elasticsearch-index-guard.sh`

- Зміни:
  - додано опцію `--reindex-force` для примусового повного `delete/rebuild` усіх Elasticsearch-записів;
  - прапорець використовує наявну безпечну гілку повної переіндексації, аналогічну `ORCHESTRATOR_ES_GUARD=force`.
