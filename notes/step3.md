# Step 3 · Three roads into bronze (Mathilde, review : Emma)

Mesures du 2026-11-03. Bucket `gs://albert-de-msc2-26-g03-bronze`, entreprise locale (`~/de/albert-marketplace`, `compose.yaml`).

## Récapitulatif

| Étape | Statut | Preuve |
|---|---|---|
| Entreprise locale | ✅ | 5 services, `wal_level = logical`, topic `clickstream` qui grossit |
| Extracteur `orders` : 3 runs | ✅ | curseur 0 → 50 000 → 223 167 → 223 174 |
| Test de retry | ✅ | 4 avertissements (2, 4, 8, 16 s) puis abandon, curseur inchangé |
| Consumer vers le bronze | ✅ | 1 111 événements dans `bronze/clickstream/dt=2026-09-16` et `dt=2026-09-17` |
| DLQ | ✅ | 3 événements cassés dans `bronze/_dlq/clickstream/dt=2026-11-03/`, consumer toujours vivant |
| Extracteur `customer` sans `pwd` | ✅ | 130 786 lignes, `SELECT pwd` → `Unrecognized name: pwd` |
| Connecteur Airbyte (route 1) | ❌ | permission refusée dans le projet partagé : on passe en route 3 (voir plus bas) |
| Tables externes `g03_bronze.customer_extract_external` et `g03_bronze.clickstream_dlq` | ✅ | créées à la main par Mathilde dans la console BigQuery (le mode automatique de Claude Code avait bloqué leur création) ; preuves dans `ingestion/proof/dlq.txt` et `ingestion/proof/customer_columns.txt` |

## Extracteur `orders` (`ingestion/extract_orders.py`)

Curseur sur `order_id` stocké dans `bronze/_state/extract_orders.json`. Base locale : 223 088 commandes au départ.

**Run 1** (limite par défaut 50 000). Lancé par erreur pendant le test de retry (la base n'avait pas été arrêtée), gardé comme premier run normal.

```
INFO pas de curseur : premier run, lecture depuis le début
INFO curseur actuel : order_id > 0
INFO 50000 lignes -> gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-11-03/orders-20261103T171342-from-0.parquet
{"last_order_id": 50000, "rows_last_run": 50000, "updated_at": "2026-11-03T17:13:43.501699+00:00"}
```

**Run 2** (`BATCH_LIMIT=250000`, rattrapage de l'historique)

```
INFO curseur actuel : order_id > 50000
INFO 173118 lignes -> gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-11-03/orders-20261103T172217-from-50000.parquet ; curseur 50000 -> 223167
{"last_order_id": 223167, "rows_last_run": 173118, "updated_at": "2026-11-03T17:22:18.821213+00:00"}
```

**Run 3** (limite par défaut, 4 minutes après : seulement les nouvelles commandes)

```
INFO curseur actuel : order_id > 223167
INFO 7 lignes -> gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-11-03/orders-20261103T172636-from-223167.parquet ; curseur 223167 -> 223174
{"last_order_id": 223174, "rows_last_run": 7, "updated_at": "2026-11-03T17:26:36.516197+00:00"}
```

Total : 50 000 + 173 118 + 7 = 223 125 commandes en bronze, sans trou ni recouvrement (chaque run repart du curseur précédent).

**Test de retry** (base arrêtée avec `docker compose -f compose.yaml stop db`)

```
INFO curseur actuel : order_id > 223174
WARNING connexion échouée (tentative 1/5), nouvel essai dans 2s
WARNING connexion échouée (tentative 2/5), nouvel essai dans 4s
WARNING connexion échouée (tentative 3/5), nouvel essai dans 8s
WARNING connexion échouée (tentative 4/5), nouvel essai dans 16s
ERROR abandon après 5 tentatives
{"last_order_id": 223174, ...}   curseur inchangé : rien de perdu, rien d'avancé à tort
```

Mode intervalle (`INTERVAL_START` / `INTERVAL_END`) ajouté pour le DAG du step 7 et l'image d'Emma (guide 7.2) : chemin fixe par jour, rejouer = remplacer le même objet.

## Extracteur `customer` sans `pwd` (`ingestion/extract_customer.py`)

Liste de colonnes explicite (`c_id, fname, lname, phone, email`), jamais de `SELECT *` : une colonne secrète ou ajoutée plus tard n'arrive pas en bronze sans décision. Instantané complet par jour (chemin fixe, idempotent) parce que `c_id` est une chaîne aléatoire : aucun curseur incrémental possible.

```
INFO 130786 lignes, colonnes ['c_id', 'fname', 'lname', 'phone', 'email', '_extracted_at'] -> gs://albert-de-msc2-26-g03-bronze/bronze/extract/customer/extract_date=2026-11-03/customer.parquet
```

**Preuve que `pwd` n'existe pas**, par une table externe temporaire BigQuery (`bq query --external_table_definition`) sur le fichier écrit :

```
SELECT * FROM customer_bronze LIMIT 1          -> c_id,fname,lname,phone,email,_extracted_at
SELECT COUNT(*), COUNT(DISTINCT c_id)          -> 130786, 130786
SELECT pwd FROM customer_bronze LIMIT 1        -> Unrecognized name: pwd at [1:8]
```

Et par le schéma du Parquet lu directement : `['c_id', 'fname', 'lname', 'phone', 'email', '_extracted_at']`, `pwd présent : False`.

Puis par la table externe `g03_bronze.customer_extract_external`, créée à la main par Mathilde dans la console BigQuery (le mode automatique de Claude Code avait bloqué sa création) : `INFORMATION_SCHEMA.COLUMNS` donne `c_id, fname, lname, phone, email, _extracted_at, extract_date`, `grep -c pwd` → 0. Sortie : `ingestion/proof/customer_columns.txt`.

`phone` et `email` restent des données personnelles en bronze : à classer au step 10.

## Clickstream (`ingestion/consume_clickstream.py`, `ingestion/clickstream.schema.json`)

Champs réels observés sur 47 messages du topic :

| `event_type` | champs en plus du tronc commun |
|---|---|
| `product_viewed` | `p_id`, `price` |
| `added_to_cart` | `p_id`, `qty`, `price` |
| `order_placed` | `order_id`, `amount`, `currency`, `payment_method`, `items[{p_id, qty, price}]` (pas de `p_id` ni `qty` au niveau racine) |

Schéma : tronc commun obligatoire, exigences par type (`added_to_cart` exige `p_id` et `qty`, `order_placed` exige `order_id` et `items`), `additionalProperties: true`. 47/47 vrais événements valides. `rfc3339-validator` ajouté aux dépendances : sans lui, jsonschema ne vérifie pas le format `date-time` et `event_time = "hier"` était accepté (il aurait créé un dossier `dt=hier`).

Run du consumer (2 min 30, arrêt par Ctrl-C) :

```
INFO 1052 événements -> .../bronze/clickstream/dt=2026-09-16/batch-20261103T175738-12c26d9b.parquet
WARNING 3 rejetés -> .../bronze/_dlq/clickstream/dt=2026-11-03/rejected-20261103T175738-12c26d9b.parquet
INFO 24 événements -> .../bronze/clickstream/dt=2026-09-16/batch-20261103T175839-a077f395.parquet
INFO 3 événements -> .../bronze/clickstream/dt=2026-09-17/batch-20261103T175839-a077f395.parquet
INFO 32 événements -> .../bronze/clickstream/dt=2026-09-17/batch-20261103T175909-e67c7255.parquet
```

DLQ (3 événements cassés envoyés à 18:57:09, le consumer a continué à écrire après) :

| reason | raw |
|---|---|
| `schema_v1: qty: '2' is not of type 'integer', 'null'` | `{... "event_id": "test-broken-1", ..., "qty": "2"}` |
| `invalid_json: Expecting value: line 1 column 1 (char 0)` | `ceci n'est pas du json` |
| `unknown_schema_version: 99` | `{"schema_version": 99, "event_id": "test-broken-3"}` |

Lu d'abord directement dans le Parquet de la DLQ, puis dans la table externe `g03_bronze.clickstream_dlq`, créée à la main par Mathilde dans la console BigQuery (le mode automatique de Claude Code avait bloqué sa création). Sortie de la requête : `ingestion/proof/dlq.txt` (3 lignes, une raison chacune).

**Risque connu** : `qty` et `order_id` sont écrits en float quand un lot mélange des types d'événements (valeurs manquantes), en entier sinon. Une table externe sur `bronze/clickstream/` pourra refuser ce mélange de types entre fichiers.

## Connecteur Airbyte : non déployé, route 3

Airbyte local tourne, mais la destination GCS exige un service account `g03-airbyte-writer` avec une clé HMAC. Nos comptes n'ont pas les droits pour créer un service account ni lire l'IAM du projet partagé `data-engineering-i1` :

```
$ gcloud projects get-iam-policy data-engineering-i1 ...
ERROR: (gcloud.projects.get-iam-policy) [mmaudet@albertschool.com] does not have permission to access projects instance [data-engineering-i1:getIamPolicy] (or it may not exist): The caller does not have permission.

$ gcloud iam service-accounts list --filter="email~^g03-"
ERROR: (gcloud.iam.service-accounts.list) [mmaudet@albertschool.com] does not have permission to access projects instance [data-engineering-i1] (or it may not exist): Permission 'iam.serviceAccounts.list' denied on resource '//cloudresourcemanager.googleapis.com/projects/data-engineering-i1' (or it may not exist).
```

Décision : route 3 (pas de connecteur). Les colonnes secrètes sont exclues par code : `customer` par liste de colonnes explicite, `payment_details` (`card_no`, `cvv`) n'est pas extraite.

Avant que Laura partage les droits sur `g03_bronze`, la création de table y était aussi refusée :

```
Access Denied: Dataset data-engineering-i1:g03_bronze: Permission bigquery.tables.create denied on dataset data-engineering-i1:g03_bronze (or it may not exist).
```

## Choix techniques (pour l'oral)

- Curseur `orders` dans le bucket, pas en local : il survit à la machine comme au conteneur.
- Curseur avancé APRÈS l'écriture du Parquet (at-least-once) : un crash relit un lot, les doublons partent en silver.
- Offsets Kafka commités APRÈS l'écriture du lot (at-least-once), l'inverse du piège du lab `l11-review`.
- Un message invalide part en DLQ avec sa raison et n'arrête jamais le consumer.
- `customer` : liste de colonnes explicite, pour qu'aucune colonne secrète n'arrive par défaut.

## Récapitulatif final

| Étape | Statut | Preuve |
|---|---|---|
| Extracteur `orders`, 3 runs | ✅ | curseur 0 → 50 000 → 223 167 → 223 174 ; commit `518920d` |
| Test de retry | ✅ | 4 avertissements (2, 4, 8, 16 s), abandon, curseur inchangé |
| Extracteur `customer` sans `pwd` | ✅ | 130 786 lignes ; `ingestion/proof/customer_columns.txt`, `grep -c pwd` → 0 ; commit `a5d2659` |
| Consumer et DLQ | ✅ | 3 événements cassés dans `g03_bronze.clickstream_dlq` (`ingestion/proof/dlq.txt`) ; commits `49a2017`, `840aed4` |
| Tables externes `clickstream_dlq` et `customer_extract_external` | ✅ | créées à la main par Mathilde (création bloquée par le mode automatique de Claude Code) ; commit `cd64bb7` |
| `qty` et `order_id` en `Int64` | ✅ | anciens fichiers `double` (4), nouveaux `int64` (2) ; un lot de 2 `product_viewed` n'a pas ces colonnes ; commit `4d470f9` |
| `docs/ingestion-failure-modes.md` | ✅ | commit `ceb7473` |
| `docs/adr/0003-ingestion-modes.md` | ✅ | commit `fb7b04e` |
| Connecteur Airbyte (route 1) | ❌ | création de service account refusée dans `data-engineering-i1` : route 3 |
| PR | ✅ | https://github.com/lucasduthu/Group-3-Data-Eng-CLoud-Infra/pull/2, reviewer `eneumayer-lang` |
