# Gouvernance des données · groupe 3

Mis à jour le 2026-11-19 (step 10, Laura). Colonnes relevées dans `INFORMATION_SCHEMA.COLUMNS`
(`notes/step10-all-columns.txt`). Le propriétaire est la personne qui peut répondre aux questions sur la
colonne : celle qui a construit la couche.

## 1. Les classes

| Classe | Ce qu'elle contient | Protection |
|---|---|---|
| `internal` | Données métier sans contenu personnel : produits, prix, quantités, dates, notes, pays, ville | Droits sur le dataset |
| `pii.identifier` | Identifiant d'une personne, sans moyen de la contacter : `buyer_id`, `c_id` | Droits sur le dataset (non tagué, voir écart 4) |
| `pii.contact` | Identifie ou permet de contacter une personne : rue, téléphone, code postal, nom, prénom, email | Policy tag `pii_contact` (taxonomie `g03-classification`) |
| `unclassified` | Texte libre : peut contenir n'importe quoi, y compris des données personnelles. On ne sait pas le classer | Traité comme `pii.contact` dans la matrice d'accès |

Les colonnes techniques (`Unnamed__0`, `ingest_date`, `month`, `dt`, `_extracted_at`, `extract_date`,
`kafka_*`) sont `internal`.

## 2. Classification de chaque colonne

### Bronze (`g03_bronze`, fichiers du bucket) · propriétaires : Laura (export, step 2), Mathilde et Lucas (extractions et clickstream, step 3)

| Table | `pii.contact` | `pii.identifier` | `unclassified` | `internal` |
|---|---|---|---|---|
| `customer_extract_external` | `fname`, `lname`, `phone`, `email` | `c_id` | | `_extracted_at`, `extract_date` |
| `shipping_details_external` | `street_address`, `zip`, `phone` | | | `Unnamed__0`, `address_id`, `city`, `state`, `country`, `ingest_date` |
| `customer_shipping_external` | | `c_id` | | `Unnamed__0`, `address_id`, `is_default`, `ingest_date` |
| `orders_external` | | `buyer_id` | | `Unnamed__0`, `order_id`, `discount_id`, `payment_id`, `order_date`, `month` |
| `review_external` | | `buyer_id` | `r_desc`, `title` | `Unnamed__0`, `review_id`, `rating`, `seller_product_flag`, `ingest_date` |
| `product_external` | | | `p_desc` | `Unnamed__0`, `p_id`, `p_name`, `price`, `qty`, `category_id`, `ingest_date` |
| `order_items_external` | | | | `order_id`, `p_id`, `qty`, `price_at_purchase`, `month` |
| `product_reviews_external` | | | | `Unnamed__0`, `p_id`, `review_id`, `ingest_date` |
| `clickstream_dlq` | | | `raw` (événement rejeté brut, contient `buyer_id` et `session_id`) | `reason`, `rejected_at`, `kafka_partition`, `kafka_offset`, `dt` |

### Warehouse (`g03_warehouse`) · propriétaire : Emma (step 4)

| Table | `pii.contact` | `pii.identifier` | `unclassified` | `internal` |
|---|---|---|---|---|
| `shipping_details` | `street_address` 🏷, `phone` 🏷, `zip` | | | `Unnamed__0`, `address_id`, `city`, `state`, `country`, `ingest_date` |
| `customer_shipping` | | `c_id` | | `Unnamed__0`, `address_id`, `is_default`, `ingest_date` |
| `orders`, `orders_p` | | `buyer_id` | | `Unnamed__0`, `order_id`, `discount_id`, `payment_id`, `month`, `order_date` |
| `review` | | `buyer_id` | `r_desc`, `title` | `Unnamed__0`, `review_id`, `rating`, `seller_product_flag`, `ingest_date` |
| `product` | | | `p_desc` | `Unnamed__0`, `p_id`, `p_name`, `price`, `qty`, `category_id`, `ingest_date` |
| `order_items`, `order_items_p`, `order_items_pc` | | | | `order_id`, `p_id`, `qty`, `price_at_purchase`, `order_date` |
| `product_reviews`, `product_reviews_c` | | | | `Unnamed__0`, `p_id`, `review_id`, `ingest_date` |
| `mv_daily_demand`, `mv_weekly_demand` | | | | `p_id`, `order_date` / `week`, `units`, `order_lines` |

🏷 = policy tag `pii_contact` posé (`infra/policy-tags/g03_warehouse.shipping_details.json`).
`orders_p`, `order_items_p`, `order_items_pc`, `product_reviews_c` sont les copies de test du step 4.

### Silver et gold (`g03_analytics`) · propriétaire : Mathilde (step 5)

| Table | `pii.identifier` | `unclassified` | `internal` |
|---|---|---|---|
| `stg_orders` | `buyer_id` | | `order_id`, `payment_id`, `discount_id`, `order_date` |
| `stg_review` | `buyer_id` | `review_text`, `review_title` | `review_id`, `rating` |
| `stg_addresses` | `c_id` | | `country` |
| `int_order_items` | `buyer_id` | | `order_id`, `p_id`, `qty`, `price_at_purchase`, `is_zero_price_anomaly`, `order_date` |
| `stg_order_items`, `stg_product`, `stg_product_reviews`, `int_product_ratings` | | | toutes |
| `fct_order_items`, `fct_daily_demand`, `dim_product`, `dim_date` | | | toutes |

Aucune colonne `pii.contact` ne dépasse le warehouse : `stg_addresses` ne garde que le pays. Le gold ne
contient aucune donnée personnelle : c'est là que lisent l'analyste et l'équipe ML.

## 3. Matrice d'accès

| Rôle | `internal` | `pii.identifier` | `pii.contact` | `unclassified` |
|---|---|---|---|---|
| Analyste | lit (gold) | non | non | non |
| Équipe ML | lit (gold) | non | non | non |
| Ingénieur données (Lucas) | lit | lit | lit (`categoryFineGrainedReader` sur `pii_contact`) | lit |
| Pipeline (dbt, Airflow) | lit | lit (jointures) | non : n'en a pas besoin | lit |

**Pour chaque « non » :** la personne ouvre une issue GitHub qui dit quelle colonne, pour quel besoin et
jusqu'à quand. L'ingénieur données répond par l'une de ces voies :
- une vue ou un agrégat sans la donnée personnelle (le cas le plus fréquent : un pays plutôt qu'une rue) ;
- un accès `categoryFineGrainedReader` temporaire, avec une date de fin, ajouté en Terraform
  (`infra/terraform/governance.tf`) et retiré par une PR à la date prévue.

## 4. Ce qui a été appliqué

| Mesure | Preuve |
|---|---|
| Taxonomie `g03-classification` et tag `pii_contact` en Terraform, `FINE_GRAINED_ACCESS_CONTROL` activé | `infra/terraform/governance.tf`, `notes/step10-apply-taxonomy.txt` |
| Tag posé sur `shipping_details.street_address` et `phone` | `notes/step10-shipping-schema-tagged.json` |
| Lecture fine accordée au seul rôle ingénieur (Lucas) | `governance.tf` |
| Lecture du bucket bronze retirée aux Viewers du projet partagé | `notes/step10-bucket-iam-before.json` → `after.json`, commit `4745ee7` |
| Effacement d'une personne testé une fois | `docs/runbooks/erasure.md` |
| Vérifié avant de taguer : seul `stg_addresses` lit `shipping_details`, sans la rue ni le téléphone | `notes/step10-who-reads-what.txt` |

## 5. Écarts entre la matrice et la réalité

1. **Le tag ne refuse personne.** La matrice dit qu'un analyste ne lit pas `pii.contact`. On n'a pas pu
   l'appliquer : l'école donne à nos comptes `datacatalog.categories.fineGrainedGet` sur tout le projet
   `data-engineering-i1` (vérifié par `testIamPermissions`, sur le projet et sur le tag). Ce droit est la
   « deuxième clé » : notre lecture de `phone` a réussi après la pose du tag (`notes/step10-refused.txt`).
   Nous n'avons trouvé aucun compte sans ce droit pour démontrer un refus : pas de création de service
   account possible, et nos autres projets n'autorisent pas la création de taxonomie.
2. **Les rôles Analyste et Équipe ML n'existent que sur le papier.** Sans service account, chaque rôle
   est tenu par nos comptes personnels, qui ont tous les mêmes droits.
3. **Tous les membres ont `roles/admin` sur le bucket bronze.** Ce droit n'existait pas au step 2
   (`notes/step2-iam-live.json`) et personne n'a documenté qui l'a ajouté ni pourquoi. Il est plus large
   que le besoin (lire et écrire des objets) ; à réduire à `roles/storage.objectAdmin`.
4. **Les identifiants (`buyer_id`, `c_id`) ne sont pas tagués.** dbt les lit pour les jointures : les
   taguer sans donner la lecture fine au compte qui lance dbt casserait le pipeline.
5. **Le bronze n'est pas tagué.** Les tables externes (`customer_extract_external` avec nom, téléphone,
   email ; `shipping_details_external`) ne prennent pas de policy tag ; leur protection repose sur les
   droits du bucket.
6. **`zip` est classé `pii.contact` mais pas tagué** : seules les deux colonnes demandées l'ont été.
7. **Le tag disparaît si la table est recréée** : `warehouse/load_native.sql` fait un
   `CREATE OR REPLACE … SELECT *`. Après un rechargement, réappliquer
   `bq update --schema=infra/policy-tags/g03_warehouse.shipping_details.json data-engineering-i1:g03_warehouse.shipping_details`.
