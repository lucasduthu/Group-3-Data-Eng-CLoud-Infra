# Runbook · Effacer une personne (demande RGPD)

Testé une fois le 2026-11-19 par Laura, sur un vrai identifiant (`AE222BBOVZIF42YOOPNBXL4UUMYA`,
2 commandes). Preuves : `notes/step10-erasure-*`. Scripts : `warehouse/erasure/`, `scripts/pseudonymize_bronze.py`.

## Choix : pseudonymiser, pas supprimer

Les commandes et articles de la personne restent dans les chiffres (chiffre d'affaires, demande
quotidienne de l'équipe ML), rattachés à un pseudonyme. Tout ce qui l'identifie ou permet de la
contacter est effacé.

| Donnée | Traitement |
|---|---|
| `buyer_id` / `c_id` | remplacé par `pseudo_` + SHA-256(sel + identifiant), même pseudonyme partout. Le sel est aléatoire (`openssl rand -hex 16`), jamais enregistré : on ne peut pas revenir en arrière |
| `street_address`, `phone`, `zip` (adresses), `fname`, `lname`, `email` (bronze) | `NULL` |
| `title`, `r_desc` de ses avis | `NULL` : texte libre `unclassified`, il peut contenir de quoi l'identifier. La note est gardée |
| commandes, articles, note, ville, pays | gardés |

Limite assumée : en droit, une donnée pseudonymisée reste en principe une donnée personnelle.
La suppression des lignes est l'option la plus stricte ; on l'écarte pour ne pas fausser les chiffres
historiques (6 lignes sur 408 560), et on le dit.

## Étapes

Compter environ 45 minutes la première fois (dont l'écriture des scripts), une dizaine ensuite.

### 1. Retrouver la personne partout (lecture seule)

```bash
bq query --use_legacy_sql=false --location=europe-west1 --project_id=data-engineering-i1 --format=pretty \
  < warehouse/erasure/01_trace.sql        # changer l'identifiant dans le DECLARE en tête du fichier
```

Le 2026-11-19 : **44 lignes dans 14 tables** (`notes/step10-erasure-trace-before.txt`) : warehouse
(orders 2, order_items 6, review 1, product_reviews 1, customer_shipping 3, shipping_details 3),
copies de test du step 4 (orders_p 2, order_items_p 6, order_items_pc 6), gold (fct_order_items 6),
bronze (orders 2, review 1, customer_shipping 3, extraction customer 1).
`shipping_details` n'a pas d'identifiant client : ses lignes se retrouvent par les `address_id` de
`customer_shipping` (ici 36314, 55874, 68068).

### 2. Warehouse

```bash
SALT=$(openssl rand -hex 16)
bq query --use_legacy_sql=false --location=europe-west1 --project_id=data-engineering-i1 --format=pretty \
  --parameter=target::<identifiant> --parameter="salt::$SALT" \
  < warehouse/erasure/02_pseudonymize_warehouse.sql
```

Affiche le pseudonyme (ici `pseudo_e5824a1ad3ee622a9ad2c7a3`) et le nombre d'adresses effacées (3).
Garder le même Terminal pour l'étape 3 : le pseudonyme doit être identique partout.

### 3. Bronze (fichiers Parquet du bucket)

Un Parquet ne se modifie pas ligne par ligne : on copie le bronze en local, on réécrit les fichiers
concernés, on renvoie ceux-là seulement.

```bash
mkdir -p ~/de/bronze-erasure
gcloud storage rsync --recursive gs://albert-de-msc2-26-g03-bronze/bronze ~/de/bronze-erasure
python scripts/pseudonymize_bronze.py <identifiant> <pseudonyme> ~/de/bronze-erasure            # dry run
python scripts/pseudonymize_bronze.py <identifiant> <pseudonyme> ~/de/bronze-erasure --apply | tee apply.txt
grep '^MODIFIED ' apply.txt | while read -r _ rel; do
  gcloud storage cp ~/de/bronze-erasure/"$rel" gs://albert-de-msc2-26-g03-bronze/bronze/"$rel"
done
```

Le 2026-11-19 : 112 fichiers lus en 6 s, **10 réécrits**, 0 résidu. Le script a trouvé des fichiers
que le traçage BigQuery ne voit pas (pas de table externe) : `export/buyer`, `export/customer_payment`,
le clickstream (3 événements) et deux fichiers d'extraction `extract/orders`.
Ce qui n'a pas marché : `gcsfs` ne s'installe pas sur un Mac Intel (dépendance `cryptography` à
compiler) ; d'où le passage par une copie locale et `gcloud`.

### 4. Silver et gold

```bash
docker run --rm -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json \
  -v "$HOME/.config/gcloud:/gcloud:ro" -v "$PWD/dbt/models:/usr/app/models:ro" \
  docker.io/emmaneum/g03-dbt@sha256:524caa56c3df542e8306681f607d76b9c9ebaa450147e0a34a665c7a48061c19 \
  build --target prod
```

Les vues staging et intermédiaires suivent toutes seules ; les tables marts sont reconstruites.
Le 2026-11-19 : `PASS=46 WARN=2 ERROR=0` (les 2 avertissements sont connus depuis le step 5).
Monter `dbt/models` est nécessaire tant que l'image n'est pas reconstruite (sinon la table perd le
partitionnement du step 9).

### 5. Prouver

Relancer `01_trace.sql` : **0 partout** le 2026-11-19 (`notes/step10-erasure-trace-after.txt`).

## Les copies qui survivent

| Copie | Durée | Décision |
|---|---|---|
| Corbeille du bucket (soft delete) | 7 jours (`retentionDurationSeconds: 604800`), versioning désactivé | Gardée : c'est la protection contre les suppressions accidentelles du bronze. Les anciennes versions des 10 fichiers disparaissent seules vers le 2026-11-26 |
| Time travel BigQuery `g03_warehouse` | réduit de 168 h à **48 h** | Les versions d'avant l'effacement disparaissent vers le 2026-11-21. Coût : on ne peut plus annuler une erreur sur le warehouse au-delà de 48 h |
| Time travel `g03_bronze`, `g03_analytics` | 168 h | Laissé : les tables externes du bronze ne stockent rien, et les tables du gold ne contiennent pas l'identifiant |
| Copies locales du step 2 (`~/de/legacy_csv`, `~/de/out/bronze`) | — | Mises dans la Corbeille du Mac ; à vider après le rendu |

## Ce qui n'est pas traité

- **La base source** (PostgreSQL de l'entreprise) garde la personne. Une nouvelle extraction
  (`extract_customer.py`, `extract_orders.py`) la réintroduirait dans le bronze : l'effacement doit
  aussi être fait à la source.
- **`session_id`** du clickstream et **`payment_id`** de `customer_payment` sont gardés : ce sont des
  identifiants techniques aléatoires, mais ils relient encore des lignes entre elles.
- **Les copies de test du step 4** (`orders_p`, `order_items_p`, `order_items_pc`) ont été traitées,
  mais toute nouvelle copie devra être ajoutée à `01_trace.sql`.
