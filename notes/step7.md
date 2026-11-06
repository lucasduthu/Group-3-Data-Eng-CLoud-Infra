# Step 7 · Your pipeline, on a schedule — Lucas (review : Mathilde)

Toutes les preuves ci-dessous ont été produites le 2026-11-06 sur le Mac de Lucas
(Airflow 3.3.2, provider Docker 4.5.9, Docker Desktop 4.94 / Engine 29.8.2, arm64).
DAG : [`orchestration/dags/marketplace_g03.py`](../orchestration/dags/marketplace_g03.py),
installation : [`orchestration/README.md`](../orchestration/README.md).

## 7.1 Installer Airflow

- `~/de/l07` : compose 3.3.2, `.env`, `Dockerfile` (+ `apache-airflow-providers-docker==4.5.9`),
  `docker-compose.override.yaml` avec le socket, plus le montage
  `orchestration/dags → /opt/airflow/dags` sur les six services `airflow-*`.
- `docker compose ps` : 7/7 `(healthy)` ; UI http://localhost:8080 (`airflow`/`airflow`, HTTP 201
  sur `/auth/token`).
- `docker compose exec airflow-worker python -c "import docker; …"` → `29.8.2` (idem depuis le
  scheduler, nécessaire pour `airflow dags test`).
- `airflow dags list | grep g03` → `marketplace_g03_daily | /opt/airflow/dags/marketplace_g03.py`,
  aucune erreur d'import.

## 7.2 Extracteur pilotable par intervalle

Déjà fait au step 6 : `run_interval()` est dans `ingestion/extract_orders.py` depuis le commit
`518920d`, donc dans l'image publiée `emmaneum/g03-ingest:2026-11-05-d888406`
(`git show d888406:ingestion/extract_orders.py | grep -c INTERVAL_START` → 8). **Pas de nouveau tag
nécessaire** ; le DAG utilise le tag et l'image dbt du step 6 (`notes/step6-tag.txt`, ADR-0006 :
Docker Hub, multi-arch).

## 7.3 Le DAG — écarts par rapport au modèle du guide, et pourquoi

| Écart | Raison (constatée, pas supposée) |
|---|---|
| `schedule=CronDataIntervalTimetable("@daily")` au lieu de `"@daily"` | Airflow 3.3 : `create_cron_data_intervals = False`, donc `"@daily"` donne `data_interval_start == data_interval_end`. L'extracteur aurait lu `[jour, jour)` = 0 ligne, run vert et vide. |
| `INTERVAL_START = {{ ds }}`, `INTERVAL_END = {{ macros.ds_add(ds, 1) }}` | Avec ce timetable, `airflow tasks render … 2026-08-01` rendait `INTERVAL_START=2026-07-31` : un run manuel reçoit l'intervalle qui **finit** à sa date. `ds` vaut le jour voulu pour `dags test`, le planning et le back-fill (vérifié : rendu `2026-08-01`/`2026-08-02`, dry-run du back-fill sur 08-01 → 08-07). |
| `GOOGLE_CLOUD_PROJECT` dans l'environnement des conteneurs | 1er run : `extract_orders` en échec, `OSError: Project was not passed and could not be determined from the environment` (ADC utilisateur sans projet). |
| `load_orders` s'authentifie avec un jeton tiré des ADC (`CLOUDSDK_AUTH_ACCESS_TOKEN_FILE`) | Le compte `gcloud` actif de la machine avait une session expirée (`Reauthentication failed`) alors que les ADC fonctionnaient : les trois tâches utilisent maintenant le même identifiant. |
| MERGE : `month = FORMAT_DATE('%Y-%m', order_date)`, `CAST(discount_id AS FLOAT64)`, `Unnamed__0` laissé NULL | `g03_warehouse.orders` vient de l'export CSV du step 4 : colonnes `Unnamed__0` (index pandas), `month` (`2026-08`), `discount_id FLOAT64`. Dans la stage, `discount_id` est `INT64` (NULL partout en août). |
| Registre `docker.io/emmaneum` au lieu d'Artifact Registry | ADR-0006 (pas de droit de création du dépôt AR). |

Premier run vert, `airflow dags test marketplace_g03_daily 2026-08-01` :

```
extract_orders  163 lignes -> gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-08-01/orders.parquet
load_orders     rows_for_day = 163
dbt_build       Done. PASS=46 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=48
```

Ce run a créé le dataset de prod `g03_analytics` (il n'existait pas : le step 6 avait construit en
`dev`). Les 2 WARN sont connus (`assert_no_zero_price_lines`, 30 lignes à prix 0 ; nom produit NULL).

## 7.4 Idempotence : deux runs du même jour

```sql
SELECT COUNT(*) AS n, COUNT(DISTINCT order_id) AS distinct_ids
FROM `data-engineering-i1.g03_warehouse.orders` WHERE order_date = DATE '2026-08-01';
```

| Moment | n | distinct_ids | total `orders` | objet GCS écrit |
|---|---|---|---|---|
| après le 1er run (10:47Z) | 163 | 163 | 222 644 | `extract_date=2026-08-01/orders.parquet` |
| après le 2e run (10:50Z) | 163 | 163 | 222 644 | le même (remplacé) |

`n = distinct_ids` et rien ne bouge au 2e run. Les 163 lignes existaient déjà (chargement du step 4) :
le MERGE les a **mises à jour** (0 ligne avec `Unnamed__0 IS NULL`, c.-à-d. 0 insertion). La branche
`INSERT` n'est donc exercée que sur des jours absents de l'entrepôt (après le 2026-09-14) ; elle ne
peut pas créer de doublon (MERGE sur `order_id`, stage dédoublonnée par `QUALIFY`).

## 7.5 L'alerte arrive

Tâche cassée exprès : `INGEST_IMAGE = …/g03-ingest:2026-11-05-doesnotexist`, puis
`airflow dags test marketplace_g03_daily 2026-08-02` (10:51Z → 11:02Z) :

```
404 Client Error … failed to resolve reference "docker.io/emmaneum/g03-ingest:2026-11-05-doesnotexist"
extract_orders  up_for_retry   (essai 1)
extract_orders  up_for_retry   (essai 2, +2 min)
ALERT :red_circle: marketplace_g03_daily.extract_orders a échoué pour 2026-08-02 après 3 essais. Runbook : docs/runbooks/failed-run.md
extract_orders  failed         (essai 3, +4 min)
```

Une seule ligne `ALERT`, au dernier essai : `on_failure_callback` ne se déclenche pas sur les
retries. Le DAG a été remis au bon tag juste après.

Avec `airflow dags test`, le callback tourne dans le conteneur où on lance la commande : l'`ALERT`
est dans la sortie de la commande, pas dans `docker compose logs airflow-worker` (où elle apparaît
pour un run planifié ou de back-fill).

**Reste à faire (humain)** : mettre l'URL du webhook Slack/Discord du groupe dans `~/de/l07/.env`
(`ALERT_WEBHOOK_URL=…`), `docker compose up -d`, relancer le test ci-dessus, et faire une capture
du message reçu par une personne nommée. Le code poste `{"text": …, "content": …}` (Slack lit
`text`, Discord lit `content`).

## 7.6 Quality gate et poison row : alarme, faux verrou, vrai verrou

Poison row injectée à chaque essai (puis supprimée, `poison_left_in_source = 0` vérifié) :

```sql
INSERT INTO `data-engineering-i1.g03_warehouse.order_items` (order_id, p_id, qty, price_at_purchase, order_date)
SELECT order_id, 'POISON-ORPHAN', 1, 9.99, order_date
FROM `data-engineering-i1.g03_warehouse.orders` WHERE order_date = DATE '2026-08-03' LIMIT 1;
```

puis `airflow dags test marketplace_g03_daily 2026-08-03` et, étape 3 :
`SELECT COUNT(*) FROM g03_analytics.fct_order_items WHERE p_id = 'POISON-ORPHAN'`.
Entre deux essais, un run propre reconstruit les marts sans la poison row (compte = 0 vérifié avant
chaque injection).

| | A. Alarme | B. « Verrou » du guide | C. Verrou corrigé |
|---|---|---|---|
| DAG | `dbt_run >> dbt_test` | `dbt_build` | `dbt_build` |
| Image dbt | `g03-dbt:alarm-1278d01` (locale : 1278d01 **sans** le test staging) | `emmaneum/g03-dbt:2026-11-05-1278d01` | `emmaneum/g03-dbt:2026-11-06-cfed22c` (1278d01 + `depends_on`) |
| Test(s) en échec | `relationships_fct_order_items_p_id…dim_product`, `relationships_fct_daily_demand_p_id…dim_product` (`dbt_test` : PASS=31 WARN=2 **ERROR=2**) | les deux mêmes **+** `relationships_stg_order_items_p_id…stg_product` (PASS=43 WARN=2 **ERROR=3 SKIP=0**) | `relationships_stg_order_items_p_id…stg_product` seul (PASS=26 WARN=1 **ERROR=1 SKIP=20**) |
| Modèles sautés | aucun (`dbt_run` vert, 12/12 modèles) | **aucun** | `int_order_items`, `fct_order_items`, `fct_daily_demand` (+ leurs tests) |
| Run rouge ? | oui (`dbt_test` failed après 3 essais) | oui (`dbt_build` failed après 3 essais) | oui (`dbt_build` failed après 3 essais) |
| Alerte ? | oui : `ALERT … dbt_test a échoué pour 2026-08-03 après 3 essais` | oui : `ALERT … dbt_build …` | oui : `ALERT … dbt_build …` |
| Compte étape 3 (poison dans le mart) | **1** | **1** | **0** (`fct_order_items` non réécrite : `last_modified` identique avant/après) |
| Verdict | alarme : la valeur est publiée, puis on sonne | **alarme aussi** | **verrou** : le mart garde le dernier état sain |

### Pourquoi B n'est pas un verrou

Un test `relationships` a **deux parents** (`stg_order_items` et `stg_product`). `dbt build` ne fait
attendre un test qu'aux modèles qui descendent de **tous** ses parents (dbt-core 1.12.5,
`dbt/compilation.py`, `add_test_edges_1` : *« adds dependencies from a downstream node to an upstream
test if and only if the downstream node is already a descendant of all the nodes the upstream test
depends on »*). Or aucun modèle en aval de `stg_order_items` ne dépend de `stg_product` :
`int_order_items` lit `stg_order_items` + `stg_orders`, `fct_order_items` y ajoute `stg_addresses` et
`int_product_ratings` (avis). Le test échoue donc **en parallèle** de la construction des marts, sans
rien bloquer. Le commentaire du step 5 (« il bloque le pipeline AVANT que les marts soient
construits ») était faux.

Correctif (commit `cfed22c`) : `-- depends_on: {{ ref('stg_product') }}` dans `int_order_items.sql`.
`int_order_items` descend maintenant des deux parents, dbt ajoute l'arête test → `int_order_items`,
et l'échec saute toute la branche aval (C). Les tests à un seul parent (`not_null`,
`unique_combination_of_columns`) bloquaient déjà correctement.

**Reste à faire (Emma)** : publier `emmaneum/g03-dbt:2026-11-06-cfed22c` (amd64 + arm64, procédure
du step 6). D'ici là, l'image n'existe que sur la machine de Lucas (construite depuis `cfed22c` :
`docker build -f dbt/Dockerfile -t docker.io/emmaneum/g03-dbt:2026-11-06-cfed22c .`).

## 7.7 Back-fill

Détail dans [`step7-backfill.md`](step7-backfill.md) : prédiction écrite avant (163 / 147 / 181 /
154 / 161 / 172 / 145, total 1 123), back-fill 2026-08-01 → 2026-08-07 exécuté par le scheduler et le
worker, **0 écart** sur les 7 jours, `n = distinct_ids`. Le seul écart réel est une course entre un
run planifié et un run de back-fill sur la stage partagée, corrigée (une stage par jour).

## 7.8 Checklist

- [x] **DAG visible, run complet vert depuis le planning** : `scheduled__2026-11-06` (jour 2026-11-05)
  `success`, exécuté par le scheduler ; les 7 runs du back-fill aussi.
- [x] **Deux runs du même jour → mêmes comptes** : 163 / 163 avant et après (§7.4).
- [ ] **Alerte reçue par une personne nommée (capture)** : l'alerte part (ligne `ALERT` au dernier
  essai, §7.5) ; il manque le webhook du groupe dans `.env` et la capture.
- [x] **Poison row : alarme puis verrou documentés** : §7.6, avec le faux verrou du guide et sa correction.
- [x] **Back-fill : prédiction avant, comptes réels, écarts expliqués** : `step7-backfill.md`.

## Ce qui reste, et pour qui

| Qui | Quoi |
|---|---|
| Emma | Publier `emmaneum/g03-dbt:2026-11-06-cfed22c` (amd64 + arm64). Sans elle, le DAG ne tourne que sur la machine de Lucas. |
| Lucas | `ALERT_WEBHOOK_URL` dans `~/de/l07/.env`, relancer le test du §7.5, capture. |
| Lucas | **Au prochain démarrage d'Airflow**, mettre le DAG en pause d'abord (`airflow dags pause marketplace_g03_daily`) : un 2e back-fill (08-04 → 08-07, 4 runs en parallèle) a été interrompu et reprendrait aussitôt. Ses runs sont sans risque (idempotents) mais lourds. |
