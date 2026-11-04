-- Expérience hebdomadaire : non partitionnée, moins performante sur le test.
CREATE MATERIALIZED VIEW `data-engineering-i1.g03_warehouse.mv_weekly_demand`
CLUSTER BY p_id AS
SELECT p_id, DATE_TRUNC(order_date, WEEK) AS week,
       SUM(qty) AS units, COUNT(*) AS order_lines
FROM `data-engineering-i1.g03_warehouse.order_items_p`
GROUP BY p_id, week;

-- Référence sur des semaines complètes
SELECT
  p_id,
  SUM(qty) AS units
FROM `data-engineering-i1.g03_warehouse.order_items_p`
WHERE order_date >= DATE '2025-06-15'
  AND order_date < DATE '2025-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;

-- Même calcul sur la vue hebdomadaire
SELECT
  p_id,
  SUM(units) AS units
FROM `data-engineering-i1.g03_warehouse.mv_weekly_demand`
WHERE week >= DATE '2025-06-15'
  AND week < DATE '2025-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;

WITH depuis_table AS (
  SELECT
    p_id,
    SUM(qty) AS units
  FROM `data-engineering-i1.g03_warehouse.order_items_p`
  WHERE order_date >= DATE '2025-06-15'
    AND order_date < DATE '2025-09-14'
  GROUP BY p_id
),
depuis_vue AS (
  SELECT
    p_id,
    SUM(units) AS units
  FROM `data-engineering-i1.g03_warehouse.mv_weekly_demand`
  WHERE week >= DATE '2025-06-15'
    AND week < DATE '2025-09-14'
  GROUP BY p_id
),
ecarts AS (
  (
    SELECT * FROM depuis_table
    EXCEPT DISTINCT
    SELECT * FROM depuis_vue
  )
  UNION ALL
  (
    SELECT * FROM depuis_vue
    EXCEPT DISTINCT
    SELECT * FROM depuis_table
  )
)
SELECT COUNT(*) AS nombre_ecarts
FROM ecarts;