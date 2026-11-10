# Step 9 · FinOps (Laura, 10 novembre 2026)

## Labels (Terraform)
- Convention dans infra/terraform/locals.tf : team, course, environment, managed_by, plus component par ressource
- Appliqués sur le bucket bronze et les datasets g03_bronze, g03_warehouse, g03_analytics : Plan 0 to add, 4 to change, 0 to destroy, puis No changes
- Vérifié sur le bucket : component=bronze;course=msa-dat09-02;environment=course;managed_by=terraform;team=g03
- Les labels ne valent que pour la dépense à partir du 10 novembre : tout ce qui a été dépensé avant reste non attribuable
- Pas de labels possibles sur les bindings IAM. Le bucket de state (fait à la main) n'est pas dans Terraform, donc pas labellisé

## Optimisation mesurée
Requête : top 10 produits par unités sur 3 mois, sur g03_analytics.fct_order_items
Changement : fct_order_items partitionné par mois sur order_date, clusterisé par p_id (config dbt)

| | Date | Bytes processed | Bytes billed | Durée |
|---|---|---|---|---|
| Avant (table non partitionnée) | 2026-11-10 14:29 | 10,91 MB | 11 MB | 296 ms |
| Après (partition mois + cluster p_id) | 2026-11-10 14:51 | 977,43 KB | 10 MB | 155 ms |

- Environ 11 fois moins de données lues
- À 7,50 $/TiB : environ 0,00007 $ → 0,000007 $ par run sur les octets lus
- MAIS le facturé ne baisse presque pas (11 MB → 10 MB) : BigQuery facture 10 Mo minimum par requête. À notre échelle, le gain ne se voit pas en argent. Il devient réel au-delà de 10 Mo lus par requête, donc avec des données 10 à 100 fois plus grosses
- Ce qui aurait montré qu'on avait tort : un ratio proche de 1,0× (requête sans filtre sur order_date). Piège rencontré : le 2e lancement affichait 0 B (results cached), mesure écartée
- dbt build après changement : PASS=18 WARN=1 ERROR=0 (le warning = les 30 lignes à prix 0, déjà connues au step 5)

## Plus gros poste de coût (10 novembre)
Pas d'export de facturation exploitable dans le free tier : mesure en unités.

Calcul BigQuery, requêtes touchant les datasets g03_ (INFORMATION_SCHEMA.JOBS, 30 jours, notes/step9-bytes-per-day.txt) :

| Jour | Requêtes | GiB lus | GiB facturés |
|---|---|---|---|
| 2026-11-03 | 41 | 0,284 | 0,469 |
| 2026-11-04 | 210 | 1,082 | 2,577 |
| 2026-11-05 | 94 | 0,392 | 1,039 |
| 2026-11-06 | 916 | 3,816 | 9,878 |
| 2026-11-10 | 21 | 0,123 | 0,218 |
| Total | 1 282 | 5,697 | 14,181 |

- Plus gros poste : le calcul BigQuery à la demande (SKU Analysis). Forme : en pics, liés aux exécutions du pipeline. Le 6 novembre (step 7, Airflow et back-fill) pèse 70 % du facturé
- On facture 2,5 fois ce qu'on lit : minimum de 10 Mo facturé par requête. Beaucoup de petites requêtes coûtent plus que leurs données
- Les 7, 8 et 9 novembre manquent : jours sans activité, pas des zéros
- Premier essai de la requête faux : UNNEST(referenced_tables) comptait une requête une fois par table lue (8,2 GiB lus le 6 nov. au lieu de 3,8). Corrigé avec EXISTS

Stockage :
- Bucket bronze : 113,70 MiB (99 MiB au step 2, plus les extractions et le clickstream du step 3)
- BigQuery : environ 242 MiB sur les 15 plus grosses tables (notes/step9-storage-bq.txt). INFORMATION_SCHEMA.TABLE_STORAGE n'est pas activée sur le projet partagé : on a utilisé __TABLES__ par dataset
- Optimisation suivante identifiée : les copies de test du step 4 (order_items x3, orders x2) occupent environ 49 MiB, soit 20 % du stockage BigQuery. Non supprimées : à décider avec Emma

## Alerte budget
- Budget du projet partagé data-engineering-i1 géré par l'école. Accès refusé depuis nos comptes : billing.resourcebudgets.read et billing.resourceCosts.get manquants
- L'alerte prévient, elle does not stop la dépense. Le seul plafond réel est maximum_bytes_billed (1 Go par requête dans profiles.yml, step 4)
