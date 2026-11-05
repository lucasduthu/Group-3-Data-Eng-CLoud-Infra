# Reproduire les images Docker — Step 6

## Images publiées

Registre : Docker Hub, namespace `emmaneum`

Les deux images sont publiées pour `linux/amd64` et `linux/arm64`.

| Image | Tag |
| --- | --- |
| `docker.io/emmaneum/g03-ingest` | `2026-11-05-d888406` |
| `docker.io/emmaneum/g03-dbt` | `2026-11-05-1278d01` |

Les tags et digests complets sont conservés dans
[`notes/step6-tag.txt`](../notes/step6-tag.txt).

Les commandes suivantes utilisent les digests pour récupérer exactement
les images validées.

## Prérequis

- Docker Desktop démarré
- Google Cloud CLI installé
- Identifiants ADC créés avec `gcloud auth application-default login`
- Droits d’écriture dans le bucket bronze et dans le dataset de développement
- Droits de lecture sur les sources BigQuery de `g03_warehouse`
- Environnement `albert-marketplace` démarré selon son README, avec PostgreSQL
  accessible sous le nom `db` sur le réseau `albert-marketplace_default`
- Données PostgreSQL contenant les commandes du 1er août 2026

Les identifiants Google restent sur la machine hôte et sont montés en lecture
seule au lancement. Ils ne sont pas incorporés dans les images.

## 1. Télécharger les images validées

Dans un même terminal :

```bash
INGEST_IMAGE=docker.io/emmaneum/g03-ingest@sha256:8d8d2e8f9b2f2bd97012768a43a5267f28ff4572337e809c806294ac4d9b1a7c

DBT_IMAGE=docker.io/emmaneum/g03-dbt@sha256:524caa56c3df542e8306681f607d76b9c9ebaa450147e0a34a665c7a48061c19

docker pull "$INGEST_IMAGE"
docker pull "$DBT_IMAGE"
```

Docker sélectionne la variante correspondant à l’architecture de la machine.

## 2. Reproduire l’extraction PostgreSQL vers GCS

```bash
docker run --rm \
  --network albert-marketplace_default \
  -e DATABASE_URL=postgresql://postgres:postgres@db:5432/marketplace \
  -e BRONZE_BUCKET=albert-de-msc2-26-g03-bronze \
  -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e INTERVAL_START=2026-08-01 \
  -e INTERVAL_END=2026-08-02 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json \
  -v "$HOME/.config/gcloud:/gcloud:ro" \
  "$INGEST_IMAGE"
```

Les identifiants PostgreSQL ci-dessus correspondent à l’environnement
pédagogique local.

Résultat observé le 5 novembre 2026 : **163 lignes** extraites pour
l’intervalle `[2026-08-01, 2026-08-02)`.

Objet produit :

```text
gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-08-01/orders.parquet
```

Vérifier sa présence :

```bash
gcloud storage ls -l \
  gs://albert-de-msc2-26-g03-bronze/bronze/extract/orders/extract_date=2026-08-01/orders.parquet
```

Rejouer cet intervalle remplace le même objet sans modifier le curseur
incrémental. La métadonnée `_extracted_at` change à chaque exécution :
le fichier n’est donc pas nécessairement identique octet par octet.

Le nombre de lignes dépend du contenu de la base PostgreSQL source.

## 3. Vérifier la connexion dbt

```bash
docker run --rm \
  -e DBT_USER=emma \
  -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json \
  -v "$HOME/.config/gcloud:/gcloud:ro" \
  "$DBT_IMAGE" \
  debug --target dev
```

Résultat attendu : `All checks passed!`

Remplacer `emma` par ses propres initiales pour utiliser son dataset
`g03_dbt_<initiales>`.

## 4. Construire les modèles et exécuter les tests dbt

```bash
docker run --rm \
  -e DBT_USER=emma \
  -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json \
  -v "$HOME/.config/gcloud:/gcloud:ro" \
  "$DBT_IMAGE" \
  build --target dev
```

Cette commande crée ou remplace les modèles dans `g03_dbt_emma`.

Résultat observé avant et après récupération depuis Docker Hub :

```text
PASS=46 WARN=2 ERROR=0 SKIP=0 TOTAL=48
```

Les 48 éléments comprennent 12 modèles et 36 tests.

Avertissements observés :

- 6 produits sans nom
- 30 lignes de commande avec un prix égal à zéro

Ces deux tests sont configurés avec une sévérité `warn`.
Leurs résultats peuvent évoluer si les données sources changent.

dbt lit les tables natives existantes de `g03_warehouse`.
L’extraction vers GCS ci-dessus ne recharge pas automatiquement ces tables.

Sans arguments, l’image dbt exécute `build --target prod`, qui cible
`g03_analytics`. Les commandes de ce guide précisent `--target dev`.

## Preuves de validation

- [`step6-reproduce.txt`](../notes/step6-reproduce.txt) :
  suppression des références locales, téléchargement et nouvelles exécutions
- [`step6-ingest-manifest.txt`](../notes/step6-ingest-manifest.txt) :
  digest et architectures publiées de l’ingestion
- [`step6-dbt-manifest.txt`](../notes/step6-dbt-manifest.txt) :
  digest et architectures publiées de dbt
- [`step6-dbt-debug.txt`](../notes/step6-dbt-debug.txt) :
  configuration et connexion validées
- [`step6-dbt-build.txt`](../notes/step6-dbt-build.txt) :
  résultat du premier build dbt validé

Les digests obtenus après téléchargement correspondent à ceux des images
publiées. L’extraction a de nouveau produit 163 lignes et dbt a retrouvé
le même bilan de tests.