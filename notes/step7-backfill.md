# Step 7 · Back-fill du 2026-08-01 au 2026-08-07

## 1. Prédiction (écrite AVANT le back-fill, 2026-11-06T10:32Z)

Source : Postgres local du cours (`albert-marketplace-db-1`), requête du guide 7.7 :

```sql
SELECT order_date, COUNT(*) FROM orders
WHERE order_date >= '2026-08-01' AND order_date < '2026-08-08'
GROUP BY order_date ORDER BY order_date;
```

| order_date | commandes prédites |
|---|---|
| 2026-08-01 | 163 |
| 2026-08-02 | 147 |
| 2026-08-03 | 181 |
| 2026-08-04 | 154 |
| 2026-08-05 | 161 |
| 2026-08-06 | 172 |
| 2026-08-07 | 145 |
| **total** | **1 123** |

Hypothèses :

- Un run = un jour UTC `[data_interval_start, data_interval_end)`, donc 7 runs pour 7 jours,
  chacun lit exactement les commandes de son `order_date` (colonne `DATE`, sans fuseau : pas
  d'effet de bord à minuit).
- `g03_warehouse.orders` contient déjà ces jours (chargement du step 4, mêmes chiffres vérifiés
  le 2026-11-06). Le MERGE sur `order_id` doit donc mettre à jour les lignes existantes et n'en
  ajouter aucune : compte attendu identique à la prédiction, et `n = distinct_ids`.
- Le générateur de charge écrit des commandes datées du jour simulé (après le 2026-09-15) : il ne
  devrait pas toucher le mois d'août pendant le back-fill.

## 2. Back-fill (2026-11-06, 11:50Z → 12:12Z)

```bash
docker compose exec airflow-scheduler airflow backfill create --dag-id marketplace_g03_daily \
  --from-date 2026-08-01 --to-date 2026-08-07 --reprocess-behavior completed --max-active-runs 1 --dry-run
# 7 dates logiques, 2026-08-01 -> 2026-08-07 ; puis la même commande sans --dry-run (backfill_id=1)
```

Deux options ajoutées à la commande du guide :

- `--reprocess-behavior completed` : les `airflow dags test` du 7.3-7.6 avaient déjà laissé un run
  pour le 08-01, le 08-02 et le 08-03 ; sans cette option, le back-fill ne rejoue pas ces jours.
- `--max-active-runs 1` : explicite, voir l'écart ci-dessous.

Le back-fill est resté `queued` tant que le DAG était en pause : en Airflow 3, le scheduler n'exécute
pas les runs (back-fill compris) d'un DAG en pause. Après `airflow dags unpause`, le scheduler a
aussi créé le run planifié du dernier intervalle (`scheduled__2026-11-06`, jour traité 2026-11-05).

Résultat : 8 runs `success` (les 7 jours du back-fill et le run planifié du 2026-11-05 : `0 lignes`,
`0 commande pour 2026-11-05 dans le bronze : rien à fusionner`, dbt PASS=46).

## 3. Comparaison (12:13Z)

```sql
SELECT order_date, COUNT(*) AS n, COUNT(DISTINCT order_id) AS distinct_ids
FROM `data-engineering-i1.g03_warehouse.orders`
WHERE order_date BETWEEN '2026-08-01' AND '2026-08-07'
GROUP BY order_date ORDER BY order_date;
```

| order_date | prédit (Postgres) | réel (BigQuery) | distinct_ids | écart |
|---|---|---|---|---|
| 2026-08-01 | 163 | 163 | 163 | 0 |
| 2026-08-02 | 147 | 147 | 147 | 0 |
| 2026-08-03 | 181 | 181 | 181 | 0 |
| 2026-08-04 | 154 | 154 | 154 | 0 |
| 2026-08-05 | 161 | 161 | 161 | 0 |
| 2026-08-06 | 172 | 172 | 172 | 0 |
| 2026-08-07 | 145 | 145 | 145 | 0 |

Aucun écart. Total `g03_warehouse.orders` inchangé (222 644) : les 1 123 lignes existaient déjà
(step 4), le MERGE les a mises à jour sans en insérer (0 ligne avec `Unnamed__0 IS NULL`). Source
inchangée pendant le back-fill (mêmes 7 comptes relus à 12:13Z, `MAX(order_date) = 2026-09-19`) : le
générateur de charge n'a rien écrit en août. `order_date` est une `DATE` : pas d'effet de fuseau.
`fct_order_items` contient 296 / 312 / 314 / 277 / 318 / 343 / 272 lignes pour ces 7 jours, 0 poison row.

## 4. L'écart qui n'est pas dans les chiffres : une course entre deux runs

Le run du 08-01 a mis 13 min au lieu de ~1,5 : `load_orders` a échoué une fois puis réussi au retry.

```
Error processing job '…bqjob_r8710efb…': Value of type INT64 cannot be assigned to buyer_id, which has type STRING
```

Cause : le run planifié (2026-11-05, jour vide) et le run de back-fill du 08-01 tournaient **en même
temps** — le back-fill a son propre `max_active_runs`, celui du DAG ne le limite pas — et partageaient
la table `g03_warehouse.orders_stage`. Le run du 11-05 l'a remplacée par sa stage vide (colonnes INT64)
entre le `load` et le `MERGE` du 08-01. Ici l'erreur de type l'a rendu visible ; avec deux jours non
vides, le MERGE d'un jour aurait fusionné les lignes de l'autre, en vert, et un jour n'aurait jamais
été chargé.

Correctif : une stage par jour (`orders_stage_YYYYMMDD`), supprimée après le MERGE.

Vérifié : le script `LOAD` du DAG, exécuté tel quel pour le 2026-08-04 (seules les 3 lignes
d'authentification propres au conteneur remplacées par leur équivalent sur l'hôte) →
`Number of affected rows: 154`, `rows_for_day = 154`, stage du jour supprimée. L'ancienne table
partagée `g03_warehouse.orders_stage` a été supprimée.

**Non vérifié** : un 2e back-fill de 4 jours en parallèle (`--max-active-runs 4`), lancé pour prouver
le correctif sous concurrence, a été interrompu (la machine ne suivait pas). Le correctif supprime la
table partagée, donc la cause ; il n'a pas été rejoué en parallèle de bout en bout. En attendant :
back-fill avec `--max-active-runs 1`.
