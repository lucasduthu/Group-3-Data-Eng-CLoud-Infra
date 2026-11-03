# Step 2 · mesures (Laura, 3 novembre 2026)

## Données
- Export : 27 fichiers CSV, 197 Mo au total
- Exclues du bronze : customer (pwd) et payment_details (card_no, cvv), en attente de validation du prof
- order_items n'a pas de date : partitionné par le mois de sa commande
- orders et order_items : partition par mois (37 dossiers chacun). Autres tables : partition par date de chargement

## Tailles
| | CSV | Parquet snappy |
|---|---|---|
| Total | 197 Mo | 99 Mo (÷2) |
| orders | 13,34 Mo | 10,66 Mo |
| order_items | 10,37 Mo | 8,45 Mo |

## Bucket
- gs://albert-de-msc2-26-g03-bronze, projet data-engineering-i1, europe-west1, STANDARD, accès uniforme, accès public bloqué
- 92 objets, environ 99 Mo

## BigQuery
- Le projet data-engineering-i1 est partagé par la classe : dataset nommé g03_bronze pour éviter les conflits
- 7 tables externes. Comptes identiques aux CSV : orders 222 644, order_items 408 560, review 111 322, product_reviews 111 322, product 42 858, customer_shipping 200 001, shipping_details 200 001
- Incident : bq s'exécute en US par défaut, il faut --location=europe-west1

## Mesure du partitionnement (cache désactivé)
| Requête | Bytes processed | Durée |
|---|---|---|
| order_items sans filtre | 3,12 MB | 724 ms |
| order_items avec month = '2026-08' (9 893 lignes) | 77,29 KB | 298 ms |
- Environ 40 fois moins de données lues : BigQuery n'ouvre qu'un dossier de mois sur 37

## Lifecycle et droits
- Lifecycle appliquée : export en Nearline après 90 jours, DLQ supprimée après 90 jours (notes/step2-lifecycle-live.json)
- Droits du bucket : uniquement les rôles hérités du projet (owners, editors, viewers de data-engineering-i1). Projet partagé, donc tous les éditeurs de la classe peuvent écrire dans le bucket : à traiter au step 10

## Questions ouvertes
- customer et payment_details dans le bronze ? (réponse du prof : …)
