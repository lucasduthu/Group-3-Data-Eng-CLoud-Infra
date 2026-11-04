-- Step 5 · Recherche des défauts (Mathilde)
-- À lancer dans la console BigQuery DÈS qu'Emma a chargé les 7 tables natives (dataset g03_warehouse).
-- Reporter chaque chiffre dans le commentaire d'en-tête du modèle staging correspondant (les "À REMPLIR").

-- 1. Colonnes parasites (index pandas exporté avec le CSV)
SELECT table_name, column_name
FROM `data-engineering-i1.g03_warehouse.INFORMATION_SCHEMA.COLUMNS`
WHERE LOWER(column_name) LIKE 'unnamed%' OR column_name LIKE 'int64_field%'
ORDER BY table_name;

-- 2. Textes vides ou faits d'espaces dans les avis -> stg_review
SELECT
  COUNTIF(r_desc = '')                     AS desc_empty,
  COUNTIF(TRIM(r_desc) = '' AND r_desc != '') AS desc_blank,
  COUNTIF(r_desc IS NULL)                  AS desc_null,
  COUNTIF(title = '')                      AS title_empty,
  COUNTIF(TRIM(title) = '' AND title != '')   AS title_blank,
  COUNT(*)                                 AS total
FROM `data-engineering-i1.g03_warehouse.review`;

-- 3. Commandes en double -> stg_orders
SELECT COUNT(*) AS duplicated_order_ids FROM (
  SELECT order_id FROM `data-engineering-i1.g03_warehouse.orders`
  GROUP BY order_id HAVING COUNT(*) > 1);

-- 4. Lignes de commande en double -> stg_order_items
SELECT COUNT(*) AS duplicated_lines FROM (
  SELECT order_id, p_id FROM `data-engineering-i1.g03_warehouse.order_items`
  GROUP BY order_id, p_id HAVING COUNT(*) > 1);

-- 5. Clients avec plusieurs adresses par défaut (fan-out) -> stg_addresses
SELECT COUNT(*) AS customers_with_several_defaults FROM (
  SELECT c_id FROM `data-engineering-i1.g03_warehouse.customer_shipping`
  WHERE is_default = 1 GROUP BY c_id HAVING COUNT(*) > 1);
-- ... et clients sans adresse par défaut (ils auront country = 'UNKNOWN')
SELECT COUNT(DISTINCT o.buyer_id) AS buyers_without_default_address
FROM `data-engineering-i1.g03_warehouse.orders` o
LEFT JOIN `data-engineering-i1.g03_warehouse.customer_shipping` cs
  ON cs.c_id = o.buyer_id AND cs.is_default = 1
WHERE cs.c_id IS NULL;

-- 6. Produits : doublons et noms vides -> stg_product
SELECT
  COUNT(*) - COUNT(DISTINCT p_id)            AS duplicated_p_ids,
  COUNTIF(p_name IS NULL OR TRIM(p_name) = '') AS empty_names
FROM `data-engineering-i1.g03_warehouse.product`;

-- 7. Avis : notes hors 1-5, doublons, liens orphelins -> stg_review / stg_product_reviews
SELECT rating, COUNT(*) AS n FROM `data-engineering-i1.g03_warehouse.review` GROUP BY rating ORDER BY rating;
SELECT COUNT(*) - COUNT(DISTINCT review_id) AS duplicated_review_ids FROM `data-engineering-i1.g03_warehouse.review`;
SELECT COUNT(*) AS reviews_linked_to_unknown_product
FROM `data-engineering-i1.g03_warehouse.product_reviews` pr
LEFT JOIN `data-engineering-i1.g03_warehouse.product` p USING (p_id)
WHERE p.p_id IS NULL;

-- 8. Plage des dates de commande -> dim_date (GENERATE_DATE_ARRAY doit la couvrir)
SELECT MIN(order_date) AS first_order, MAX(order_date) AS last_order
FROM `data-engineering-i1.g03_warehouse.orders`;

-- 9. Lignes de commande dont le produit n'existe pas (le test relationships échouera dessus)
SELECT COUNT(*) AS orphan_lines
FROM `data-engineering-i1.g03_warehouse.order_items` i
LEFT JOIN `data-engineering-i1.g03_warehouse.product` p USING (p_id)
WHERE p.p_id IS NULL;
