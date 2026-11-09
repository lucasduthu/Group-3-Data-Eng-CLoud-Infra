"""Albert's Marketplace, groupe 3 : une journée de commandes.

extract (Postgres -> bronze GCS) -> load (bronze -> warehouse, idempotent)
-> dbt_build (silver + gold + tests : le quality gate).
Ce fichier dit QUOI tourne et dans QUEL ordre ; aucun travail ici.
"""
import json
import os
import urllib.request

import pendulum
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG, CronDataIntervalTimetable
from docker.types import Mount

HOST_DIR = os.environ["HOST_DIR"]
GCLOUD_DIR = os.environ["GCLOUD_DIR"]

PROJECT = "data-engineering-i1"
BUCKET = "albert-de-msc2-26-g03-bronze"
# Docker Hub et pas Artifact Registry : voir ADR-0006. Tags et digests dans notes/step6-tag.txt.
REG = "docker.io/emmaneum"
INGEST_IMAGE = f"{REG}/g03-ingest:2026-11-05-d888406"   # contient déjà le mode intervalle (commit 518920d)
# cfed22c = 1278d01 + depends_on dans int_order_items : sans lui, le test staging ne bloque pas les marts
# (notes/step7.md §7.6). Tag À PUBLIER sur Docker Hub (procédure du step 6) ; en attendant, le construire :
#   docker build -f dbt/Dockerfile -t docker.io/emmaneum/g03-dbt:2026-11-06-cfed22c .
DBT_IMAGE = f"{REG}/g03-dbt:2026-11-06-cfed22c"
DB_URL = "postgresql://postgres:postgres@db:5432/marketplace"   # base locale du cours, pas un vrai secret

gcloud_mount = Mount(source=GCLOUD_DIR, target="/gcloud-ro", type="bind", read_only=True)
# GOOGLE_CLOUD_PROJECT : des ADC "utilisateur" ne portent pas de projet, et storage.Client()
# échoue sans lui ("Project was not passed and could not be determined from the environment").
ADC = {"GOOGLE_APPLICATION_CREDENTIALS": "/gcloud-ro/application_default_credentials.json",
       "GOOGLE_CLOUD_PROJECT": PROJECT}

# Chargement idempotent d'UN jour : on remplace exactement ce jour dans la table.
# bq s'authentifie avec un jeton tiré des ADC, comme les deux autres tâches : il ne dépend
# pas du compte gcloud actif (dont la session peut expirer indépendamment).
# g03_warehouse.orders vient de l'export CSV du step 4 : Unnamed__0 (index pandas) reste NULL
# pour les lignes chargées ici, month est recalculé, discount_id est FLOAT64 dans la cible.
LOAD = f"""
set -e
cp -r /gcloud-ro /tmp/gcloud && export CLOUDSDK_CONFIG=/tmp/gcloud
gcloud auth application-default print-access-token > /tmp/token
export CLOUDSDK_AUTH_ACCESS_TOKEN_FILE=/tmp/token
DAY="$INTERVAL_START"
BQ="bq --project_id={PROJECT} --location=europe-west1"
# Une stage PAR JOUR : un run planifié et un run de back-fill tournent en même temps (le back-fill a son
# propre max_active_runs). Avec une stage commune, le MERGE d'un jour lisait la stage d'un autre (vu au
# step 7 : "Value of type INT64 cannot be assigned to buyer_id"), ou pire, un jour n'était jamais chargé.
STAGE="g03_warehouse.orders_stage_${{DAY//-/}}"
$BQ load --source_format=PARQUET --replace \
  "$STAGE" "gs://{BUCKET}/bronze/extract/orders/extract_date=$DAY/orders.parquet"
# Jour sans commande : le Parquet vide n'a que des colonnes de type NULL, chargées en INT64, et le MERGE
# échouerait sur un conflit de types (order_date, buyer_id). On le dit et on s'arrête, en vert.
N=$($BQ query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM $STAGE" | tail -1)
if [ "$N" = "0" ]; then echo "0 commande pour $DAY dans le bronze : rien à fusionner"; $BQ rm -f -t "$STAGE"; exit 0; fi
$BQ query --use_legacy_sql=false --format=none "
MERGE g03_warehouse.orders AS t
USING (SELECT order_id, buyer_id, payment_id,
              CAST(discount_id AS FLOAT64) AS discount_id, order_date
       FROM $STAGE
       WHERE TRUE
       QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id) = 1) AS s
ON t.order_id = s.order_id
WHEN MATCHED THEN UPDATE SET buyer_id = s.buyer_id, payment_id = s.payment_id,
                             discount_id = s.discount_id, order_date = s.order_date,
                             month = FORMAT_DATE('%Y-%m', s.order_date)
WHEN NOT MATCHED THEN INSERT (order_id, buyer_id, payment_id, discount_id, order_date, month)
                      VALUES (s.order_id, s.buyer_id, s.payment_id, s.discount_id, s.order_date,
                              FORMAT_DATE('%Y-%m', s.order_date))"
$BQ rm -f -t "$STAGE"
$BQ query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) AS rows_for_day FROM g03_warehouse.orders WHERE order_date = DATE '$DAY'"
"""


def alert(context):
    """Appelé seulement quand une tâche a échoué pour la DERNIÈRE fois."""
    ti = context["task_instance"]
    text = (f":red_circle: {ti.dag_id}.{ti.task_id} a échoué pour "
            f"{context['ds']} après {ti.try_number} essais. "
            f"Runbook : docs/runbooks/failed-run.md")
    print("ALERT", text, flush=True)
    url = os.environ.get("ALERT_WEBHOOK_URL")   # webhook Slack/Discord dans le .env d'Airflow, jamais dans le repo
    if url:
        req = urllib.request.Request(url, data=json.dumps({"text": text, "content": text}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10)


with DAG(
    dag_id="marketplace_g03_daily",
    # Airflow 3 : "@daily" seul donne un intervalle VIDE (data_interval_start == data_interval_end,
    # create_cron_data_intervals = False par défaut). L'extracteur lirait [jour, jour) = 0 ligne.
    # CronDataIntervalTimetable rétablit l'intervalle [jour, jour+1) du run.
    schedule=CronDataIntervalTimetable("@daily", timezone="UTC"),
    start_date=pendulum.datetime(2026, 8, 1, tz="UTC"),   # les données Postgres vont du 2023-09-15 au 2026-09-19
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 2,
        "retry_delay": pendulum.duration(minutes=2),       # plus long qu'un redémarrage de la base
        "retry_exponential_backoff": True,
        "on_failure_callback": alert,
    },
    tags=["g03", "albert"],
) as dag:

    # Le jour traité = la date logique du run. Avec CronDataIntervalTimetable, un run planifié
    # ou de back-fill a logical_date = data_interval_start, mais un run manuel (`dags test 2026-08-01`,
    # bouton Trigger) reçoit l'intervalle qui FINIT à sa date, [07-31, 08-01). {{ ds }} vaut le jour
    # voulu dans les trois cas ; data_interval_start décalerait les runs manuels d'un jour.
    interval_env = {
        "INTERVAL_START": "{{ ds }}",
        "INTERVAL_END": "{{ macros.ds_add(ds, 1) }}",
    }

    extract = DockerOperator(
        task_id="extract_orders",
        image=INGEST_IMAGE,
        network_mode="albert-marketplace_default",
        environment={"DATABASE_URL": DB_URL, "BRONZE_BUCKET": BUCKET, **ADC, **interval_env},
        mounts=[gcloud_mount],
        auto_remove="success",
        mount_tmp_dir=False,
    )

    load = DockerOperator(
        task_id="load_orders",
        image="google/cloud-sdk:slim",
        entrypoint="/bin/bash",
        command=["-c", LOAD],
        environment=interval_env,
        mounts=[gcloud_mount],
        auto_remove="success",
        mount_tmp_dir=False,
    )

    dbt_build = DockerOperator(
        task_id="dbt_build",                 # le quality gate : build teste chaque modèle et saute l'aval d'un échec
        image=DBT_IMAGE,
        command="build --target prod",
        environment={**ADC, "CLOUDSDK_CONFIG": "/gcloud-ro"},
        mounts=[gcloud_mount],
        auto_remove="success",
        mount_tmp_dir=False,
    )

    extract >> load >> dbt_build
