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
