-- Construit les variantes de comparaison sans modifier les tables initiales.
CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.orders_p`
PARTITION BY DATE_TRUNC(order_date, MONTH) AS          -- À ADAPTER : mois vs jour, à justifier
SELECT * FROM `data-engineering-i1.g03_warehouse.orders`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.order_items_p`
PARTITION BY DATE_TRUNC(order_date, MONTH) AS
SELECT * FROM `data-engineering-i1.g03_warehouse.order_items`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.order_items_pc`
PARTITION BY DATE_TRUNC(order_date, MONTH)
CLUSTER BY p_id AS
SELECT * FROM `data-engineering-i1.g03_warehouse.order_items`;

-- Clustering sur la table de jointure de Q3 (pas de date : le partitionnement n'aide pas)
CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.product_reviews_c`
CLUSTER BY review_id AS
SELECT * FROM `data-engineering-i1.g03_warehouse.product_reviews`;


-- Mesures après création des variantes ; cache désactivé.
-- Q1 après partitionnement
SELECT
  DATE_TRUNC(order_date, MONTH) AS month,
  ROUND(SUM(qty * price_at_purchase), 2) AS revenue
FROM `data-engineering-i1.g03_warehouse.order_items_p`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 12 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY month
ORDER BY month;

-- Q2 après partitionnement
SELECT
  p_id,
  SUM(qty) AS units
FROM `data-engineering-i1.g03_warehouse.order_items_p`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;

-- Q2 après partitionnement + clustering
SELECT
  p_id,
  SUM(qty) AS units
FROM `data-engineering-i1.g03_warehouse.order_items_pc`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;

-- Q3 après clustering
SELECT
  pr.p_id,
  ROUND(AVG(r.rating), 2) AS avg_rating,
  COUNT(*) AS n_reviews
FROM `data-engineering-i1.g03_warehouse.review` AS r
JOIN `data-engineering-i1.g03_warehouse.product_reviews_c` AS pr
  ON r.review_id = pr.review_id
GROUP BY pr.p_id
HAVING COUNT(*) > 50
ORDER BY avg_rating DESC, pr.p_id;