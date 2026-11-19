# Step 9 · FinOps (Laura, 10 novembre 2026)

Requêtes SQL de toutes les mesures : warehouse/finops/ (01 à 06). Sorties brutes : notes/step9-*.txt.

## Labels
- Convention dans infra/terraform/locals.tf : team, course, environment, managed_by, plus component par ressource
- Terraform : bucket bronze et datasets g03_bronze, g03_warehouse, g03_analytics. Plan 0 to add, 4 to change, 0 to destroy, puis No changes (notes/step9-plan-labels.txt, step9-apply-labels.txt, step9-no-changes.txt)
- Bucket de state gs://albert-de-msc2-26-g03-tfstate : créé à la main au step 8, Terraform ne peut pas gérer le bucket qui contient son propre state. Labellisé à la main avec managed_by=manual (notes/step9-tfstate-labels.txt)
- Pas de labels possibles sur les bindings IAM
- Les labels ne valent que pour la dépense à partir du 10 novembre : ce qui a été dépensé avant reste non attribuable

### Ce que les labels attribuent réellement
- Les labels d'un dataset ou d'un bucket attribuent le STOCKAGE. Ils ne se propagent pas aux requêtes : le coût de CALCUL BigQuery ne s'attribue que par les labels posés sur chaque job
- Mesure (warehouse/finops/05 et 06) : sur 1 283 requêtes touchant les datasets g03_ en 30 jours, 0 porte team=g03. 1 128 (88 %) portent seulement dbt_invocation_id, ajouté automatiquement par dbt. Les 155 autres (console, chargement Airflow) n'ont aucun label
- Conséquence : notre principal poste observé, le calcul, n'est pas attribuable par label aujourd'hui
- Correction proposée : faire poser team=g03 par dbt sur ses requêtes (query-comment avec job-label dans dbt_project.yml). Elle couvrirait 88 % des requêtes, mais demande une nouvelle image dbt : à faire avec la reconstruction de l'image (voir « Déploiement par Airflow »)

## Optimisation mesurée
Changement : fct_order_items partitionné par mois sur order_date, clusterisé par p_id (config dans dbt/models/marts/fct_order_items.sql)
Requête : warehouse/finops/01_benchmark_query.sql, identique avant et après (même date de début, 2026-06-14)

| | job_id | Heure (UTC) | cache_hit | Octets lus | Octets facturés |
|---|---|---|---|---|---|
| Avant (table non partitionnée) | job_axZV-paIKYWiSmzoPQCJouqLy3w8 | 2026-11-10 13:29:21 | false | 11 439 680 | 11 534 336 |
| Après (partition mois + cluster p_id) | job_-VSYAFt4Cp4mZj6QiW-FkZXRswF7 | 2026-11-10 13:51:00 | false | 1 000 888 | 10 485 760 |
| Relance écartée | job_HkkQIfQWLb09mGJgmovtv5R9sdUE | 2026-11-10 13:51:04 | true | 0 | 0 |

- Source : INFORMATION_SCHEMA.JOBS_BY_USER (warehouse/finops/02, notes/step9-benchmark-jobs.txt)
- Résultats identiques : 0 ligne différente entre les résultats des deux jobs (warehouse/finops/03, notes/step9-benchmark-same-results.txt)
- 11,4 fois moins d'octets lus
- À 7,50 $/TiB : environ 0,000078 $ → 0,0000068 $ par run sur les octets lus
- MAIS le facturé ne baisse presque pas (11 534 336 → 10 485 760 octets) : BigQuery facture 10 Mo minimum par requête. À notre échelle, le gain ne se voit pas en argent. Il devient réel au-delà de 10 Mo lus par requête, donc avec des données 10 à 100 fois plus grosses
- Les durées (296 ms → 155 ms) viennent d'une seule mesure chacune : elles ne prouvent pas un gain de performance stable. L'argument repose sur les octets lus
- Ce qui aurait montré qu'on avait tort : un ratio proche de 1,0× (requête sans filtre sur order_date)
- dbt build après changement : PASS=18 WARN=1 ERROR=0 (le warning = les 30 lignes à prix 0, connues au step 5)

### Déploiement par Airflow (pas encore garanti)
- Le build ci-dessus a été lancé avec l'image dbt du step 6 en montant les modèles locaux (-v dbt/models:/usr/app/models:ro)
- Le DAG utilise l'image g03-dbt:2026-11-06-cfed22c (orchestration/dags/marketplace_g03.py), construite le 6 novembre avec COPY dbt/ et sans montage des modèles
- Conséquence : au prochain run du DAG, fct_order_items serait recréée SANS partitionnement, et l'optimisation disparaîtrait
- À faire après le merge : Emma reconstruit et publie l'image dbt depuis main, Lucas met à jour DBT_IMAGE dans le DAG. Tant que ce n'est pas fait, l'optimisation n'est pas déployée durablement

## Consommation BigQuery observée
Pas d'accès à la facturation (voir « Alerte budget ») : mesure en unités, ce n'est pas le coût global du projet.
Requête : warehouse/finops/04_bytes_per_day.sql (notes/step9-bytes-per-day.txt) : requêtes lisant un dataset g03_, 30 jours, chaque requête comptée une fois (EXISTS), jobs parents SCRIPT exclus.

| Jour | Requêtes | GiB lus | GiB facturés |
|---|---|---|---|
| 2026-11-03 | 41 | 0,284 | 0,469 |
| 2026-11-04 | 210 | 1,082 | 2,577 |
| 2026-11-05 | 94 | 0,392 | 1,039 |
| 2026-11-06 | 916 | 3,816 | 9,878 |
| 2026-11-10 | 22 | 0,123 | 0,218 |
| Total | 1 283 | 5,697 | 14,181 |

- Principal poste de consommation observé : le calcul BigQuery à la demande. Forme : en pics, liés aux exécutions du pipeline. Le 6 novembre (step 7, Airflow et back-fill) pèse 70 % du facturé
- On facture 2,5 fois ce qu'on lit : minimum de 10 Mo facturé par requête. Beaucoup de petites requêtes coûtent plus que leurs données
- Les 7, 8 et 9 novembre manquent : jours sans activité, pas des zéros
- Exclure les jobs SCRIPT ne change aucun chiffre : pas de double comptage parent/enfant ici
- Premier essai faux : UNNEST(referenced_tables) comptait une requête une fois par table lue (8,2 GiB lus le 6 nov. au lieu de 3,8). Corrigé avec EXISTS

Stockage :
- Bucket bronze : 113,70 MiB (99 MiB au step 2, plus les extractions et le clickstream du step 3)
- BigQuery : environ 242 MiB sur les 15 plus grosses tables (notes/step9-storage-bq.txt). INFORMATION_SCHEMA.TABLE_STORAGE n'est pas activée sur le projet partagé : on a utilisé __TABLES__ par dataset
- Optimisation suivante identifiée : les copies de test du step 4 (order_items x3, orders x2) occupent environ 49 MiB, soit 20 % du stockage BigQuery. Non supprimées : à décider avec Emma

## Alerte budget
- Budget du projet partagé data-engineering-i1 géré par l'école. Accès refusé depuis nos comptes : billing.resourcebudgets.read et billing.resourceCosts.get manquants
- Destinataire voulu pour le groupe : Laura (loldakowski@albertschool.com)
- Pas de demande envoyée : le budget reste géré par l'école et aucune alerte n'atteint le groupe. Écart assumé
- L'alerte prévient, elle does not stop la dépense. Le seul plafond réel est maximum_bytes_billed (1 Go par requête dans profiles.yml, step 4)
