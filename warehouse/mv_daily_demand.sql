-- Première création uniquement ; échoue si la vue existe déjà.
CREATE MATERIALIZED VIEW `data-engineering-i1.g03_warehouse.mv_daily_demand`
PARTITION BY DATE_TRUNC(order_date, MONTH)
CLUSTER BY p_id AS
SELECT p_id, order_date, SUM(qty) AS units, COUNT(*) AS order_lines
FROM `data-engineering-i1.g03_warehouse.order_items_p`
GROUP BY p_id, order_date;

-- Q2 sur la vue matérialisée quotidienne
SELECT
  p_id,
  SUM(units) AS units
FROM `data-engineering-i1.g03_warehouse.mv_daily_demand`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;
