SELECT
  COUNT(*) AS total_orders,
  COUNTIF(order_date IS NULL) AS dates_nulles,
  MIN(order_date) AS premiere_date,
  MAX(order_date) AS derniere_date
FROM `data-engineering-i1.g03_warehouse.orders`;

SELECT
  (
    SELECT COUNT(*)
    FROM `data-engineering-i1.g03_bronze.order_items_external`
  ) AS lignes_source,
  COUNT(*) AS lignes_warehouse,
  COUNTIF(order_date IS NULL) AS dates_nulles
FROM `data-engineering-i1.g03_warehouse.order_items`;

SELECT 'orders' AS table_name, COUNT(*) AS lignes
FROM `data-engineering-i1.g03_warehouse.orders`

UNION ALL
SELECT 'order_items', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.order_items`

UNION ALL
SELECT 'review', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.review`

UNION ALL
SELECT 'product_reviews', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.product_reviews`

UNION ALL
SELECT 'product', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.product`

UNION ALL
SELECT 'customer_shipping', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.customer_shipping`

UNION ALL
SELECT 'shipping_details', COUNT(*)
FROM `data-engineering-i1.g03_warehouse.shipping_details`

ORDER BY table_name;

SELECT
  partition_id,
  total_rows,
  ROUND(total_logical_bytes / 1024 / 1024, 2) AS taille_mib
FROM `data-engineering-i1.g03_warehouse.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'order_items_p'
ORDER BY partition_id;

WITH product_days AS (
  SELECT
    p_id,
    order_date,
    COUNT(*) AS n_lines
  FROM `data-engineering-i1.g03_warehouse.order_items_p`
  GROUP BY p_id, order_date
)
SELECT
  SUM(n_lines) AS lignes_commandes,
  COUNT(*) AS lignes_apres_agregation,
  ROUND(
    SAFE_DIVIDE(SUM(n_lines), COUNT(*)),
    2
  ) AS collapse_ratio
FROM product_days;

WITH product_weeks AS (
  SELECT
    p_id,
    DATE_TRUNC(order_date, WEEK) AS week,
    COUNT(*) AS n_lines
  FROM `data-engineering-i1.g03_warehouse.order_items_p`
  GROUP BY p_id, week
)
SELECT
  SUM(n_lines) AS lignes_commandes,
  COUNT(*) AS lignes_apres_agregation,
  ROUND(
    SAFE_DIVIDE(SUM(n_lines), COUNT(*)),
    2
  ) AS collapse_ratio_semaine
FROM product_weeks;