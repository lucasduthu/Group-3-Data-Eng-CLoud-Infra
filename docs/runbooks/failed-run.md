# Runbook : un run de `marketplace_g03_daily` a échoué

L'alerte n'arrive qu'après le **dernier** essai (2 retries, 2 puis 4 min) : l'échec n'est pas
passager. Le message donne la tâche et le jour (`ds`).

## 1. Lire le log de la tâche

UI Airflow (http://localhost:8080) → DAG `marketplace_g03_daily` → run du jour → tâche en rouge → Logs.
Ou : `docker compose logs airflow-worker | grep -A40 <task_id>` dans `~/de/l07`.

| Tâche | Symptôme fréquent | Cause probable |
|---|---|---|
| `extract_orders` | `could not translate host name "db"` | stack `albert-marketplace` arrêtée : `docker compose up -d db` dans son dossier |
| `extract_orders` | `manifest unknown` / `pull access denied` | tag d'image inexistant dans `INGEST_IMAGE` |
| `load_orders` | `Reauthentication failed` / `invalid_grant` | ADC expirées : `gcloud auth application-default login` |
| `load_orders` | `Not found: URI gs://…/extract_date=<ds>/orders.parquet` | `extract_orders` n'a rien écrit pour ce jour |
| `dbt_build` | `Failure in test …` puis `SKIP` sur les marts | **le quality gate a fait son travail** : une donnée source viole un test (voir §3) |

## 2. Rejouer la tâche à la main, hors Airflow

Les commandes complètes (avec les montages) sont dans
`orchestration/README.md` §« Lancer une tâche à la main ». Changer une chose à la fois.

## 3. Si c'est le quality gate (`dbt_build` rouge sur un test)

- Les marts n'ont **pas** été reconstruits : `g03_analytics` contient encore les chiffres du dernier
  run vert. Ne pas relancer en boucle, ça ne corrige rien.
- Trouver les lignes fautives : la requête du test est dans le log (`compiled code at …`).
- Corriger la source (ou la règle, avec une décision écrite), puis relancer.

## 4. Relancer

Chaque tâche est idempotente (chemin GCS fixe par jour, `--replace` + `MERGE` sur `order_id`,
`CREATE OR REPLACE` en dbt) : on peut relancer le run entier sans risque de doublon.
UI → run → *Clear* sur la tâche en échec (« Downstream » coché), ou :

```bash
docker compose exec airflow-scheduler airflow tasks clear marketplace_g03_daily -s <ds> -e <ds> -y
```

Vérifier ensuite que le jour n'a pas de doublon :

```sql
SELECT COUNT(*) AS n, COUNT(DISTINCT order_id) AS distinct_ids
FROM `data-engineering-i1.g03_warehouse.orders` WHERE order_date = DATE '<ds>';
```
