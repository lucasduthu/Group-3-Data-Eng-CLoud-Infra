# Orchestration

`dags/marketplace_g03.py` : le DAG `marketplace_g03_daily`, une journée de commandes par run.

```
extract_orders  ->  load_orders  ->  dbt_build
Postgres -> GCS     GCS -> BigQuery   staging + marts + tests (le quality gate)
(g03-ingest)        (cloud-sdk, bq)   (g03-dbt)
```

Chaque tâche est un conteneur (`DockerOperator`) lancé par le Docker de la machine hôte. Le DAG ne
fait aucun travail lui-même. Retries : 2 (2 puis 4 min) ; après le dernier échec, `alert()` imprime
`ALERT …` dans le log et poste sur `ALERT_WEBHOOK_URL` s'il est défini. Runbook :
[`docs/runbooks/failed-run.md`](../docs/runbooks/failed-run.md).

## Installer (une fois par machine)

Suivre le setup du cours (`DataEngineering_2_Setup.md`, leçon 07) dans `~/de/l07`, puis :

1. `.env` (chemins **absolus**, pas de `~`) :
   ```
   AIRFLOW_UID=50000
   HOST_DIR=/Users/<vous>/de/l07
   GCLOUD_DIR=/Users/<vous>/.config/gcloud
   ALERT_WEBHOOK_URL=            # webhook Slack/Discord du groupe ; jamais dans le repo
   ```
2. `docker-compose.override.yaml` du cours, plus sur **chaque** service `airflow-*` :
   ```yaml
       environment:
         ALERT_WEBHOOK_URL: ${ALERT_WEBHOOK_URL:-}
       volumes:
         - "<chemin-du-repo>/orchestration/dags:/opt/airflow/dags"
   ```
   (guillemets obligatoires si le chemin contient un espace). Compose fusionne les `volumes` par
   cible : cette ligne remplace le `./dags` du fichier de base.
3. La base du cours doit tourner : `docker compose up -d db` dans le dossier `albert-marketplace`
   (le DAG rejoint le réseau `albert-marketplace_default` et lit l'hôte `db`).
4. Des ADC valides : `gcloud auth application-default login` (les trois tâches s'authentifient avec
   elles ; le compte `gcloud` actif n'est pas utilisé).
5. `docker compose up -d`, puis :
   ```bash
   docker compose exec airflow-scheduler airflow dags list | grep g03
   ```

## Deux pièges Airflow 3 corrigés dans le DAG

- **`schedule="@daily"` donne un intervalle vide** en Airflow 3 (`create_cron_data_intervals = False` :
  `data_interval_start == data_interval_end`). Le DAG utilise `CronDataIntervalTimetable("@daily")`.
- **Un run manuel reçoit l'intervalle qui finit à sa date** (`dags test … 2026-08-01` → `[07-31, 08-01)`),
  alors qu'un run planifié ou de back-fill commence à sa date. Le jour traité est donc `{{ ds }}`, qui
  vaut le bon jour dans les trois cas.

## Lancer

```bash
# un jour, sans le scheduler (logs dans le terminal)
docker compose exec airflow-scheduler airflow dags test marketplace_g03_daily 2026-08-01
# une plage, exécutée par le scheduler et le worker (le DAG ne doit pas être en pause)
docker compose exec airflow-scheduler airflow backfill create \
  --dag-id marketplace_g03_daily --from-date 2026-08-01 --to-date 2026-08-07 \
  --reprocess-behavior completed --max-active-runs 1
```

`--reprocess-behavior completed` rejoue aussi les jours qui ont déjà un run ; `--max-active-runs 1`
évite de lancer plusieurs `dbt build` complets en même temps (chaque run reconstruit tous les modèles).

## Lancer une tâche à la main

Le même conteneur que la tâche, sans Airflow, pour lire toute la sortie. Remplacer `<GCLOUD_DIR>` et
le jour.

```bash
# extract_orders (la stack albert-marketplace doit tourner)
docker run --rm --network albert-marketplace_default -v "<GCLOUD_DIR>:/gcloud-ro:ro" \
  -e DATABASE_URL=postgresql://postgres:postgres@db:5432/marketplace \
  -e BRONZE_BUCKET=albert-de-msc2-26-g03-bronze -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud-ro/application_default_credentials.json \
  -e INTERVAL_START=2026-08-01 -e INTERVAL_END=2026-08-02 \
  docker.io/emmaneum/g03-ingest:2026-11-05-d888406
```

```bash
# dbt_build (debug d'abord : les credentials arrivent-ils ?)
docker run --rm -v "<GCLOUD_DIR>:/gcloud-ro:ro" -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud-ro/application_default_credentials.json \
  docker.io/emmaneum/g03-dbt:2026-11-05-1278d01 debug --target prod
```

`load_orders` est un script bash : ouvrir un shell dans `google/cloud-sdk:slim` avec le même montage
et exécuter les lignes de `LOAD` (dans le DAG) une par une.

Preuves du step 7 : [`notes/step7.md`](../notes/step7.md).
